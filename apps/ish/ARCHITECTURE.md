# ish — Architecture

> Tier-5 data center grade shell design for Tattva OS.
> Written in pure x86-64 assembly. Zero dependencies. No libc. No syscall boundary.

---

## Design Goals

1. **Unikernel-native** — Everything is a `call`, not a syscall. The shell runs in ring 0
   alongside the kernel. No context switch to userspace when running commands.
2. **Library-first** — Every command logic lives in `lib/cmd/` as a callable function.
   The shell is just the REPL that calls them. Other apps (dashboard, debugger, installer)
   can call the same functions.
3. **Frontend-agnostic** — The shell never touches UART or canvas directly. It talks
   through an `io_frontend_t` vtable. Swap UART for canvas terminal with zero shell changes.
4. **Extensible** — Commands register themselves via `cmd_entry_t`. Add new commands
   without modifying the dispatcher.
5. **Enterprise-grade** — Consistent exit codes, structured error handling, job control,
   environment variables, `.ishrc` config, and unit tests.

---

## Layer Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│  Tier 0: Kernel (MMU, scheduler, drivers, memory)                   │
├─────────────────────────────────────────────────────────────────────┤
│  Tier 1: lib/cmd/* — reusable command libraries                     │
│  Tier 1: lib/io/, lib/str/, lib/env/ — core primitives              │
├─────────────────────────────────────────────────────────────────────┤
│  Tier 2: apps/ish/ — Ishana Shell (REPL, parser, executor, jobs)   │
│  Tier 2: apps/ish/src/io/ — I/O frontends (UART, Canvas)            │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

| Module | Responsibility |
|--------|---------------|
| `src/main.asm` | Shell entry: init context, REPL loop, shutdown |
| `src/io/frontend.asm` | Dispatch to frontend vtable methods |
| `src/io/uart.asm` | UART/serial I/O (headless console) |
| `src/io/canvas.asm` | Canvas terminal I/O (future GUI) |
| `src/line/readline.asm` | Buffered line input with editing |
| `src/line/history.asm` | Command history ring buffer |
| `src/line/completion.asm` | Tab completion |
| `src/line/edit.asm` | Backspace, cursor movement, kill/yank |
| `src/parser/tokenizer.asm` | Split line into tokens (quotes, escapes) |
| `src/parser/expander.asm` | `$VAR`, alias, tilde expansion |
| `src/parser/grammar.asm` | Pipelines, redirection, `&&`, `||`, `;` |
| `src/exec/dispatcher.asm` | Command lookup & dispatch |
| `src/exec/cmd_registry_init.asm` | Register all builtins at startup |
| `src/exec/external.asm` | Load external app binaries as fibers |
| `src/exec/builtins/*.asm` | Shell builtins: cd, echo, exit, help, pwd, etc. |
| `src/job/job_control.asm` | `&`, `bg`, `fg`, `wait`, `jobs` |
| `src/env/environment.asm` | KEY=VALUE environment store |
| `src/env/config.asm` | `.ishrc` parsing |
| `src/util/argv.asm` | argc/argv helpers |
| `src/util/strutil.asm` | String compare, trim, case folding |
| `lib/cmd/*` | Reusable command libraries (fs, system, net, mem, ai, obs, sec, text, storage) |

---

## Command ABI

All commands follow the System V AMD64 ABI convention:

```nasm
; Input:
;   rdi = argc (u32)
;   rsi = argv (pointer to array of char* pointers)
; Output:
;   rax = exit code (0 = success, 1–255 = failure)
; Clobbers: rax, rcx, rdx, rsi, rdi, r8-r11 (caller-saved)
; Preserves: rbx, rbp, r12-r15 (callee-saved)
```

Example:

```nasm
CMD_FUNC(cmd_echo):
    PROLOGUE_SAVE rbx, rcx
    ; ... implementation ...
    xor     rax, rax              ; return 0
    EPILOGUE_RESTORE rbx, rcx
    ret
```

---

## Command Registry

Commands register themselves at init time by filling a `cmd_entry_t` and calling
`exec_register_command`. The dispatcher performs a linear scan (or hash lookup in
future) by command name.

```nasm
struc cmd_entry_t
    .magic      resd 1      ; 0x434D4401
    .name       resq 1      ; "ls", "cat", "echo"
    .handler    resq 1      ; fn(argc, argv) -> exit_code
    .help       resq 1      ; help string
    .usage      resq 1      ; usage string
    .flags      resd 1      ; CMD_FLAG_BUILTIN, CMD_FLAG_EXTERNAL, etc.
    .min_args   resd 1
    .max_args   resd 1
    .category   resq 1      ; "fs", "system", "net", "ai", "obs", "sec"
    .next       resq 1
endstruc
```

---

## I/O Frontend Abstraction

The shell never references UART or canvas registers directly. All output goes through
`io_frontend_t`:

```nasm
struc io_frontend_t
    .init       resq 1
    .read_line  resq 1
    .write      resq 1
    .write_str  resq 1
    .write_char resq 1
    .set_prompt resq 1
    .clear_line resq 1
    .get_char   resq 1
    .is_tty     resq 1
    .get_size   resq 1
    .private    resq 1
endstruc
```

Adding a new output method (canvas, VGA, pipe, network) requires only a new frontend
implementation — zero changes to shell core.

---

## Job Control Model

TattvaOS uses a cooperative fiber scheduler (`kernel/sched/`). The shell reuses it:

- Foreground commands: shell yields fiber until child completes.
- Background commands (`&`): shell creates fiber, prints job ID, returns immediately.
- `jobs`, `fg`, `bg`, `kill` manage the job table.

No preemption, no race conditions, no userspace.

---

## Environment & Configuration

- Environment variables stored as `env_var_t` linked list: `KEY=VALUE`.
- `.ishrc` parsed at boot: `set PATH=/bin:/usr/bin`, `alias ll=ls -la`, `prompt=tattva> `.
- Aliases expanded by `parser/expander.asm` before command dispatch.

---

## Error Handling

Every command returns `eax = exit code`. Standard UNIX codes:

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Shell builtin misuse |
| 127 | Command not found |
| 128 | Invalid exit argument |
| 128+N | Fatal signal N |

Errors are logged via `lib/ulog` and printed to the active frontend.

---

## Testing

Unit tests live in `tests/unit/`:

- `test_parser.asm` — tokenizer, expander, grammar
- `test_executor.asm` — dispatcher, builtins, exit codes

Run with the Tattva OS test harness.

---

## Future Work

- Pipes (`|`), redirection (`>`, `>>`, `<`)
- Logical operators (`&&`, `||`, `;`)
- Command substitution (`$(...)`)
- Globbing (`*`, `?`)
- Scripting (`ish script.ish`)
- Remote shell over TCP

---

## License

Apache-2.0 — Utkarsha Labs © 2026

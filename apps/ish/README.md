# ish — Ishana Shell

> Enterprise-grade command shell for Utkarsha OS.
> Headless-first (UART/serial), canvas-ready (GUI terminal), unikernel-native.
> Built as an application inside `apps/`, not as a separate `tools/` layer.

---

## What is ish?

`ish` (Ishana Shell) is the primary user interface for Utkarsha OS. It runs in ring 0
alongside the kernel — there is no syscall boundary, no `fork`/`exec`, and no userspace.
Every command is a direct `call` into a library function in `lib/cmd/`, making the shell
both a user application and a programmable REPL for the entire OS.

---

## Architecture

`ish` is built in layers:

```
┌─────────────────────────────────────────────────────────────┐
│  Application Layer — ish (this directory)                   │
├─────────────────────────────────────────────────────────────┤
│  Frontend  │ Line Discipline  │ Parser      │ Executor     │
│  (UART/    │ (history, edit)  │ (tokenize,  │ (dispatch,   │
│   Canvas)  │                  │   expand)   │   jobs)      │
├─────────────────────────────────────────────────────────────┤
│  Command Registry (builtin + external commands)             │
├─────────────────────────────────────────────────────────────┤
│  lib/cmd/* — reusable command libraries                     │
│  lib/io/, lib/str/, lib/umath/, lib/env/ — core primitives  │
└─────────────────────────────────────────────────────────────┘
```

Every command follows the same ABI:

```nasm
; args:  rdi = argc (u32), rsi = argv (char **)
; out:   rax = exit code (0 = success, 1–255 = failure)
```

This means `ls`, `cat`, `udis`, `ainfer`, and every other command can be called
from:
- The shell (`ish`)
- A dashboard application
- An installer or provisioning tool
- Any other Utkarsha OS app

---

## Directory Layout

```
apps/ish/
├── README.md            # this file
├── ARCHITECTURE.md      # detailed design decisions
├── Makefile             # build this shell image
├── linker.ld            # ELF/flat binary layout
├── inc/                 # public headers (structures, constants, ABIs)
│   ├── ish.inc
│   ├── frontend.inc
│   ├── cmd_registry.inc
│   ├── env.inc
│   ├── executor.inc
│   ├── job.inc
│   ├── errors.inc
│   ├── config.inc
│   └── signals.inc
├── src/                 # shell implementation
│   ├── main.asm         # entry point: init, REPL loop, shutdown
│   ├── io/
│   │   ├── frontend.asm # frontend dispatcher
│   │   ├── uart.asm     # UART/serial (headless)
│   │   └── canvas.asm   # canvas terminal (future)
│   ├── line/
│   │   ├── readline.asm # buffered input with editing
│   │   ├── history.asm  # command history ring
│   │   ├── completion.asm
│   │   └── edit.asm
│   ├── parser/
│   │   ├── tokenizer.asm
│   │   ├── expander.asm # $VAR, alias, tilde expansion
│   │   └── grammar.asm  # pipelines, redirection, && || ;
│   ├── exec/
│   │   ├── dispatcher.asm   # command lookup & dispatch
│   │   ├── cmd_registry_init.asm
│   │   ├── external.asm     # run external app binaries as fibers
│   │   └── builtins/
│   │       ├── alias.asm    cd.asm     echo.asm     exit.asm
│   │       ├── help.asm     pwd.asm     export.asm   unset.asm
│   │       ├── set.asm      unset.asm   kill.asm     jobs.asm
│   │       ├── fg.asm       bg.asm     reboot.asm   shutdown.asm
│   │       ├── env.asm      read.asm   history.asm  source.asm
│   │       └── ...
│   ├── job/
│   │   └── job_control.asm  # &, bg, fg, wait, jobs
│   ├── env/
│   │   ├── environment.asm  # KEY=VALUE store
│   │   └── config.asm       # .ishrc parsing
│   └── util/
│       ├── argv.asm         # argc/argv helpers
│       └── strutil.asm      # string compare, trim, fold
├── lib/
│   └── cmd/               # reusable command libraries (any app can call)
│       ├── fs/            ls.asm cat.asm cp.asm mv.asm rm.asm ...
│       ├── system/        ps.asm top.asm uptime.asm reboot.asm ...
│       ├── net/           ping.asm ip.asm route.asm netstat.asm ...
│       ├── mem/           free.asm vmstat.asm lscpu.asm lsmem.asm ...
│       ├── ai/            ainfer.asm aitoken.asm aimodel.asm ...
│       ├── obs/           umark.asm uprof.asm uflame.asm ...
│       ├── sec/           chmod.asm chown.asm passwd.asm sha256sum.asm ...
│       ├── text/          grep.asm sed.asm awk.asm wc.asm ...
│       └── storage/       dd.asm mkfs.asm fsck.asm lsblk.asm ...
├── config/
│   └── ishrc.example
└── tests/
    └── unit/
        ├── test_parser.asm
        └── test_executor.asm
```

---

## Build

```bash
make                  # build apps/ish/ish.img
make run              # run under QEMU with serial console
make clean            # remove build artifacts
```

---

## Roadmap

| Phase | Milestone |
|-------|-----------|
| 1 | Headless shell over UART: `help`, `echo`, `exit`, `pwd`, `cd`, `ls`, `cat` |
| 2 | Environment variables, `.ishrc`, aliases, command history |
| 3 | External command loading (run apps as fibers) |
| 4 | Job control: `&`, `bg`, `fg`, `jobs`, `kill` |
| 5 | Canvas terminal frontend (same shell logic, GUI window) |
| 6 | Pipes, redirection, `&&`, `||`, `;` |

---

## License

Apache-2.0 — Utkarsha Labs © 2026

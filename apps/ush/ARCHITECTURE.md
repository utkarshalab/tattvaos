# Ush architecture

The runnable shell is a serialized native assembly core with an explicit frontend
contract. Commands are direct calls, suitable for the OS's single-address-space
model. The Linux runner is a development frontend, not a compatibility layer in
the native shell.

```text
Linux terminal (src/host.asm)       Native COM1 (src/io/uart.asm)
                \                  /
                io_frontend_t callbacks
                         |
                   src/main.asm
           ush_init / ush_main / ush_execute
                         |
            bounded history -> command-list preparation
                                      |
                           quote-aware tokenizer/expansion
                         |            |
                         |       owned environment
                         |
              registry lookup and argc validation
                         |
         builtin handlers / persistent calculator session
```

## Modules in the build

| Module | Responsibility |
|---|---|
| `src/main.asm` | Initialize state, read/execute loop, status and exit lifecycle |
| `src/io/frontend.asm` | Tail-dispatch callbacks through the active frontend |
| `src/parser/chain.asm` | Quote-aware list splitting and preflight of every segment |
| `src/parser/tokenizer.asm` | Bounded tokens, quoting, escapes, validation/runtime expansion |
| `src/env/environment.asm` | Fixed 32-slot environment with owned name/value copies |
| `src/line/history.asm` | Bounded 32-line history ring |
| `src/line/editor.asm` | Shared VT editor, draft/history navigation and diagnostic redraw |
| `src/exec/dispatcher.asm` | Registry lookup and handler dispatch; preserve argc/argv |
| `src/exec/cmd_registry_init.asm` | Register implemented commands with argument limits |
| `src/exec/builtins/core.asm` | Builtins and calculator integration |
| `../calculator/src/` | Existing integer/scientific evaluators and persistent session |
| `src/exec/builtins/files.asm` | Persistent file/directory mutation and path helpers |
| `src/exec/builtins/filetools.asm` | Byte-based inspection, counts, line tools and search |
| `src/exec/builtins/uedit.asm` | Terminal/UXFS adapter for the native Uedit app |
| `../uedit/src/` | Bounded editing engine and VT terminal session |
| `src/exec/builtins/system.asm` | Clear/time/wait/power handlers and platform hooks |
| `src/host_platform.asm` | Linux boot clock and nanosleep; no host power control |
| `../../storage/uxfs/volume.asm` | Validated dual-bank persistent UXFS v2 store |
| `src/host_disk.asm` | Explicit disk image, locking, pread/pwrite/fsync callbacks |
| `src/io/ata.asm` | Native secondary-master IDE transfers/flush, bounded polling |
| `src/host.asm` | Linux-only startup, terminal detection, read/write/exit |
| `src/io/uart.asm` | Native polling COM1 frontend; no host syscalls |

## Execution and state

`ush_execute` bounds and records the original line, then `chain_prepare` splits
unquoted `;`, `&&`, `||` into at most 128 command descriptors. It validates every
segment with expansion disabled before dispatching any handler. Syntax errors in
later segments therefore cannot execute an earlier command accidentally. Trailing
semicolons are allowed, dangling AND/OR and empty interior commands are rejected.

Execution walks descriptors left to right. Semicolon is unconditional; AND/OR
consult the last executed status and share precedence. Skipped commands perform
no expansions or side effects. Eligible segments are tokenized into a separate
4096-byte token buffer and NULL-terminated argv array, with current environment
values. History keeps the original whole line once. Exit stops list evaluation.

Expansion occurs while lexing, respecting quote state. Expanded values are copied
into token storage as literal text; they cannot introduce operators or new argv
entries. Names/values are separately owned by the environment. Unsupported operators
cause a syntax error before any handler runs. This grammar has no pipelines,
redirection, substitutions, grouping, aliases or jobs. Expansion-size errors are
data-dependent and may occur after previous segments have updated the environment.

The dispatcher preserves argc/argv across lookup, enforces each entry's argument
counts and calls its handler using `rdi=argc`, `rsi=argv`. Handlers return status in
rax. Registry entries are writable linked records initialized from a fixed list.
The shell stores the result for `$?`, `status`, EOF and default `exit` behavior.

State is fixed-size BSS; no allocator, storage or loader is required. The active
frontend, argv, environment, history and calculator context are global to one shell
instance. Access must be serialized. Calculator state persists across invocations.

## Frontend and embedding contract

`ush_main(frontend, flags)` returns the final status. `ush_init(frontend)` and
`ush_execute(line)` also support a caller-managed loop. Callers must honor
`ush_exit_requested`. The interactive flag controls banner/prompt emission.

I/O wrappers use the implicit active frontend so command handlers can call
`frontend_write_str(rdi=text)`, matching the calculator callback. The wrapper
falls back to the length-based write callback if write_str is absent. Read uses
`frontend_read_line(rdi=buffer,rsi=capacity)`. Interactive frontends with get_char
use the common editor; line callbacks remain the fallback for pipes/test frontends.
The editor owns prompt rendering, ASCII insertion/deletion, basic VT navigation,
history/draft recall and Ctrl-C/D handling. The Linux runner supplies raw byte input
and restores termios on exit and handled termination signals.

`kernel_ush_log_begin/end` wrap complete background messages. Both the heartbeat
and console are cooperative BSP-affine fibers: editing/render operations never
yield, and the heartbeat can only run when UART input polling yields. Begin erases
the current row; end redraws the prompt, 64-column text viewport and cursor.
Other background writers must use those hooks. Fatal diagnostics bypass them.

Init/shutdown are optional. Callback
arguments, return codes and limits are specified in [README.md](README.md).

All boundaries use System V AMD64 callee-saved registers and stack alignment.
UMath/calculator calls require the normal x87/SSE floating-point environment.
`io_frontend_t_size` and `cmd_entry_t_size` determine their actual record sizes.

## Build gates

`make` produces a static host executable and a relocatable native object.
`make test` runs end-to-end command tests and a native memory-frontend ABI harness.
The latter exercises the real native entry without executing UART instructions.
Neither output is a bootable OS image on its own. The production boot build
embeds the native object using `scripts/kernel_bundle.py` and
`kernel/entry/ush.asm`. GNU ld resolves section addresses after NASM assigns the
kernel layout; the final bytes are installed before ULF stamping. The loader owns
and zeros the complete BSS extent and maps only the declared text prefix executable.

The kernel creates one BSP-affine cooperative console fiber. A UART idle hook
calls `fiber_yield`; shell exit returns to the scheduler without restarting the
console. No external executable loader or new syscall boundary is involved.
`make -C boot ush-test` exercises production BIOS/UEFI kernels, including SMP and
strict-NX firmware. See [qualification evidence](docs/KERNEL_QEMU.md). Physical
hardware remains a separate gate.

Remaining old source/header/test files describe unfinished features and are not
linked into this build. Startup config/history persistence,
external UBF applications, jobs and a Canvas frontend remain future integration.

## Persistent storage

Filesystem handlers call the working UXFS v2 volume engine, not the legacy VFS
stubs. Explicit backend callbacks transfer sectors and flush storage. Initialization
mounts a valid existing image or leaves filesystem commands unavailable; it never
formats a disk. Mutations commit an inactive bank and flush before publishing its
checksummed generation header. Runtime I/O failures disable the mount. Namespace
and directory moves are preflighted before mutation; all operations are serialized
on the cooperative BSP console. See [the volume contract](../../storage/uxfs/PERSISTENT_VOLUME.md).

The private native platform hooks return boot-monotonic nanoseconds, wait with
cooperative `fiber_yield`, and invoke chipset power control. The bundle publishes
hook offsets; the kernel installs them before Ush initialization. Shutdown/reset
handlers call `uxv_sync` first and do not invoke power on failure. The QEMU power
hook uses the existing locked PCI config API to identify PIIX4/ICH9, discover PMBASE
for S5, or issue CF9 reset. Unsupported platforms return failure. Host tests install
fake hooks to prove ABI, argument bounds, flush ordering and fail-closed behavior;
QEMU tests require actual guest RESET/SHUTDOWN events and reboot persistence.

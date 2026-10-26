# ush â€” Utkarsha Shell

A native x86-64 assembly command shell. The shell core has no heap,
libc, or Linux syscall dependency. I/O goes through a caller-supplied frontend.
The runnable build provides builtins, the calculator, and persistent UXFS v2
file/directory commands. External application loading is not implemented.
`vcs diff` compares the repository worktree with HEAD, `vcs diff --staged`
compares indexed paths, `vcs diff ID1 ID2` compares commits, and
`vcs diff FILE1 FILE2` retains direct regular-file comparison. None modifies storage.
It returns 0 for identical files, 1 for differences and 2 for errors. Output uses
space/minus/plus line prefixes, escapes control/non-ASCII bytes as `\xHH`, and
marks missing final newlines. Limits are 256 lines and the UXFS 4096-byte file
capacity. `vcs init [DIRECTORY]` creates versioned repository metadata in an
existing directory (default: current), preserving files and validating existing
metadata without rewriting it. `vcs status`, staging, commit/log/show,
restore/checkout, refs, merge/conflicts, rebase, signed identities, and `vcs check` implement a
bounded local workflow: 15 regular files per snapshot, unchanged blob reuse,
atomic UXFS publication, and SHA-256 integrity records from `lib/crypto`.
These changes are implemented but not built/tested yet; validation was deferred.
Multiline messages use repeated `-m` paragraphs or `-F FILE`; normal log output
preserves and indents LF-separated lines, while `log --oneline` escapes them.
`vcs --help` shows usage.
See the [persistent volume guide](../../storage/uxfs/PERSISTENT_VOLUME.md) for
formatting, attaching an image, bounds, recovery semantics and tests.

## Build and run

With NASM, GNU ld, make and Python 3 in Linux/WSL:

```sh
make
./build/ush
./build/ush -c 'echo "hello from Ush"'
./build/ush -c 'calc "sqrt(81) + 2**3"'
make test
```

`make` produces:

- `build/ush`: static Linux development terminal. Only `src/host.asm`, `src/host_disk.asm`, and `src/host_platform.asm` contain
  Linux syscalls. It detects terminal input, prints prompts only for a terminal,
  and also accepts piped lines or a single `-c` command.
- `build/ush-native.o`: relocatable shell plus calculator, UXFS volume, native IDE and COM1
  frontend. It contains no host runner and has no unresolved symbols. Link it
  into an OS image; it is not itself a boot image.

## Working commands

| Command | Behavior |
|---|---|
| `help` | List the commands actually registered |
| `echo [-n] [arguments...]` | Print arguments, optionally without trailing newline |
| `true`, `false` | Return status 0 or 1 |
| `status` | Print previous status; `$?` also expands to it |
| `version` | Print shell version |
| `export [NAME=VALUE ...]` | Set owned shell variables; no arguments lists them |
| `env` | List shell variables |
| `unset NAME [...]` | Remove shell variables |
| `history [-c]` | Show/clear the last 32 nonblank input lines |
| `calc [mode] "expression"` | Evaluate using the assembly calculator |
| `calc` | Enter its interactive session; `quit` returns to Ush |
| `pwd`, `ls [DIR]`, `cd [DIR]` | Inspect/navigate the mounted UXFS volume |
| `cat FILE`, `touch FILE`, `mkdir DIR` | Read files, create empty files/directories |
| `write FILE TEXT` | Create/replace file contents without shell redirection |
| `cp SOURCE DEST` | Copy a regular file; refuse an existing destination |
| `mv SOURCE DEST` | Rename a file/directory subtree; refuse overwrite/cycles |
| `rm FILE`, `rmdir DIR` | Delete files/empty directories and reclaim records |
| `append FILE TEXT` | Append contents or create a missing file |
| `stat PATH`, `df`, `du [PATH]` | Type/size, record capacity, logical byte usage |
| `head [-n N] FILE`, `tail [-n N] FILE` | First/last N LF-delimited lines (default 10) |
| `wc FILE` | Newline, ASCII-whitespace word and byte counts |
| `grep TEXT FILE` | Literal matching lines; statuses 0 match, 1 absent, 2 error |
| `find [DIR [NAME]]` | Walk a subtree; optional exact basename match |
| `hexdump FILE` | Hex offsets/bytes and printable ASCII |
| `clear`, `uptime`, `sleep SECONDS` | VT clear, seconds since boot, cooperative wait |
| `shutdown`, `reboot` | Flush storage and power off/reset the native guest |
| `uedit FILE` | Native terminal text editor; Ctrl-S save, Ctrl-Q quit |
| `exit [0..255]` | Exit with an explicit status or the previous status |

Example session:

```text
ush> export USER=utkarsha
ush> echo "Hello, $USER"
Hello, utkarsha
ush> calc "x=9"
9
ush> calc "sqrt(x)"
3
ush> calc
calc> deg
Degrees
calc> sin(30)
0.5
calc> quit
Bye.
ush> false
ush> echo $?
1
ush> exit
```

The calculator session persists between calculator invocations within the shell,
including modes, variables, answers, memory and calculator history. Use
`calc --science "expression"` or `calc -d/-x/-b "expression"` to select arithmetic
explicitly. See [calculator documentation](../calculator/README.md).

## Parsing and variable rules

- Spaces/tabs separate arguments; single and double quotes are removed. Adjacent
  quoted/unquoted segments form one argument. Empty quotes preserve an empty arg.
- Single quotes preserve literal text, including `$`. Double quotes allow variable
  expansion. Backslash escapes the next character outside single quotes, including
  inside double quotes; this is deliberately a smaller grammar than POSIX shells.
- `$NAME`, `${NAME}`, and `$?` expand. Unset variables expand to an empty string.
  Expansion stays inside one argument: no field splitting, globbing or evaluation.
- `#` begins a comment only at an unquoted token boundary.
- Unterminated quotes, trailing backslashes, invalid braced expansion and capacity
  overruns reject the whole command before dispatch. Partial input is never run.
- `;` separates commands; `&&` runs the next command on success, `||` on failure.
  AND/OR have equal precedence and associate left; a semicolon resets the condition.
  A trailing semicolon is accepted. Quote or escape operators to pass them literally.
- Every segment is syntax/argument-count validated before any command runs.
  Expansion occurs only when an eligible command executes, so
  `export X=live; echo "$X"` sees the new value and skipped commands have no effects.
  Data-dependent expansion/capacity errors can still occur after earlier commands.
- Single `|`/`&`, `<`, `>`, unquoted backticks and `$(` remain rejected. Pipelines,
  redirection, substitutions, aliases, grouping and job control are not implemented.

Variables are shell-owned copies, not pointers into a reused input buffer. Names
follow `[A-Za-z_][A-Za-z0-9_]*`, at most 63 bytes. Values hold at most 255 bytes;
there are 32 slots. The store starts empty and does not import the Linux host's
secrets/environment. Export/unset of multiple arguments applies sequentially;
earlier successful updates remain if a later argument fails.

Input/expanded token storage is limited to 4096 bytes, including terminators,
with at most 256 arguments per command and 128 commands per submitted line. History retains 32 lines,
including rejected commands/comments and the `history` command itself. It is
memory-only; startup config and history persistence await storage integration.

The terminal runner drains overlong or NUL-bearing lines before accepting the
next command, processes a final unterminated line at EOF, and exits with the last
command's status. Blank/comment-only commands preserve the previous status.
Diagnostics use the same frontend output stream as normal output. Host I/O failure
terminates with status 1. Ctrl-C cancels input and sets shell status 130. Other statuses include syntax/usage 2, unavailable handler
126 and unknown command 127; calculator evaluation passes through its own statuses.

## Interactive editing

Both Linux TTY and native UART use the same assembly editor:

| Key | Action |
|---|---|
| Left/Right | Move the cursor; typing inserts at that position |
| Home/End or Ctrl-A/E | Move to start/end |
| Backspace/Delete | Remove before/under the cursor |
| Up/Down | Recall shell history; Down restores an unfinished draft |
| Ctrl-U/K | Clear the line / delete from cursor to end |
| Ctrl-C | Discard input, reprompt, set status 130; no command is executed |
| Ctrl-D | EOF on an empty line; otherwise delete under the cursor |

The calculator uses the same editor; Ctrl-C discards only its current input,
Ctrl-D returns to Ush, and shell-history recall is disabled inside its smaller
input buffer. Cancelled input is not saved in history.

This first editor handles printable ASCII and the listed basic VT key sequences.
It renders a horizontally scrolling 64-character viewport, intended for terminals
at least 72 columns wide. Unicode grapheme widths, modified arrow keys, completion
and terminal-size-aware redraw are not implemented. Input storage still supports
4095 bytes; display width does not truncate the buffered command.

The Linux TTY frontend disables canonical input, echo and signal interpretation
so Ctrl-C reaches the shared editor. It restores the original termios on normal
exit and handled external HUP/INT/TERM/PIPE signals. Piped input uses the bounded
line reader without ANSI rendering or raw-terminal setup.

Frontends can supply `get_char() -> byte / -1 EOF / -3 I/O` to enable editing in
interactive mode. Without it, the read_line callback remains the fallback. Prompt
setup uses `frontend_set_prompt(rdi=static text, rsi=allow history)`; read_line then
renders the prompt itself. All callback and editor operations must be serialized.

## Native embedding

Use System V AMD64 calls:

```text
ush_main(rdi = io_frontend_t*, rsi = flags) -> rax = final exit status
ush_init(rdi = io_frontend_t*)             -> rax = 0 success / 1 invalid frontend
ush_execute(rdi = NUL command line)        -> rax = status
```

`USH_FLAG_INTERACTIVE` (bit 0) enables banners/prompts. Other old flag definitions
are reserved; login/restricted/noexec modes are not implemented. For a kernel UART
session, pass `&uart_frontend` and `USH_FLAG_INTERACTIVE` to `ush_main`.
For direct `ush_execute` calls, initialize first and stop when `ush_exit_requested`
becomes nonzero. `ush_last_status` exposes the last command result.

`inc/frontend.inc` defines the vtable. Required callbacks:

- `read_line(rdi=buffer, rsi=capacity)`: return length excluding NUL, -1 for EOF,
  -2 for an invalid/oversized line, -3 for I/O failure, or -4 for cancelled input. Successful lines must
  be NUL terminated, no longer than capacity-1. Consume invalid lines in full.
- `write(rdi=bytes, rsi=length)` or `write_str(rdi=NUL string)`. Both callbacks
  return void. Strings passed to write_str must be consumed before returning.

Optional init/shutdown callbacks take no arguments. Every callback must preserve
System V callee-saved registers. All stack call sites maintain 16-byte alignment.
The native COM1 frontend configures 115200 baud, 8N1 and provides polling input,
local echo, backspace and Ctrl-D. Its privileged instructions are for kernel use.
An optional `uart_idle_hook` yields while waiting for input; the kernel installs
its cooperative scheduler callback. UART input is exercised in the production
kernel under QEMU; physical hardware has not been tested.

State is static and bounded (roughly 734 KiB, including the volume/snapshot buffers), with one serialized
shell instance per linked core. It is not reentrant or safe for concurrent shells.
The calculator and math routines also need an initialized x87/SSE environment with
standard masked exceptions/rounding. Input pointers must be readable through NUL;
caller buffers/frontends must satisfy the contracts above.

## Build scope and verification

The Makefile explicitly links implemented source files. Older files under
`src/exec/builtins/`, `src/env/config.asm`, `src/line/readline.asm`, legacy headers,
`linker.ld`, and older unit-test scaffolds are retained but not linked by this gate.
Those legacy scaffolds do not qualify process supervision, external loading,
configuration or job control. The filesystem commands use the separately tested
UXFS v2 volume implementation.

`make test` checks the actual shell executable for quoting, expansion, owned
variables, capacity/reclamation, history wraparound, dispatch, status/exit, malformed
input recovery, EOF and nested calculator sessions, plus 120 generated quoting
cases. A memory-backed frontend harness checks native ush_main, callback argument
flow, stack alignment, callee-saved registers and shutdown. These are focused host
checks. Separate volume tests cover remount persistence, namespace/capacity errors,
image locking, corruption recovery and partial writes/flush failures. Production kernel linking and interactive QEMU qualification are covered
by the separate gate below; hardware remains untested.

## Production kernel and QEMU

From the repository root:

```sh
make -C boot img
make -C boot ush-test
make -C boot run
```

The boot build statically embeds Ush in the ULF kernel. `kernel/entry/ush.asm`
queues one cooperative BSP-affine console fiber after the existing heartbeat.
Idle UART polls yield; `exit` terminates only the shell fiber. Heartbeat diagnostics
also run on the BSP and pair `kernel_ush_log_begin/end`: they clear the input row,
print their complete line, then restore the prompt, visible text and cursor.
Other normal background console writers must use the same paired hooks. Fatal
exception output remains immediate and bypasses prompt restoration.

The existing kernel is a flat NASM translation unit. `scripts/kernel_bundle.py`
uses GNU ld to resolve the separate native object's relocations at the actual
kernel-assigned text/rodata/data/BSS addresses. NASM includes provisional section
bytes; the build then replaces them with the final linked bytes before stamping
the ULF size/checksum and atomically publishing the image. No handwritten
relocations or runtime loader are involved. Text remains inside the ULF executable
prefix, and all data/BSS remains within its owned, non-executable footprint.
The build requires host Python 3 and GNU binutils in addition to NASM/make.

`ush-test` validates image integrity, bundle ownership and four real-kernel serial
sessions: SeaBIOS (1 CPU), OVMF (1 and 4 CPUs), and strict-NX OVMF (1 CPU). It checks
editing/history recall, Ctrl-C status, command-list short-circuiting, mid-line
heartbeat/cursor restoration, variables, calculator recovery, idle scheduler
progress and shell exit. See [kernel/QEMU evidence](docs/KERNEL_QEMU.md).
This gate qualifies this integration in QEMU; it is not a claim that the entire
boot regression matrix or physical hardware was requalified.

## File tools and platform commands

The text tools consume file bytes, including NUL, without modifying files. Line
boundaries are LF; final unterminated lines are preserved by head/tail/grep. `wc`
counts LF bytes and words separated by ASCII space/tab/LF/CR/VT/FF. `grep` matches
literal bytes, not regular expressions; `find` matches an exact basename, not a
glob. No pipeline, redirection or locale/Unicode classification is implied.
`head`/`tail` accept a separate `-n COUNT` with 0..2147483647; the default is ten.
`du` reports logical file bytes, while `df` reports records including root plus
logical data bytes and the 4096-byte file ceiling, not free space in a host image.

`rm` handles one regular file. `rmdir` requires an empty directory and refuses
root, the current directory and its ancestors. Successful deletion zeroes/reclaims
the record and persists it. Old snapshots can retain prior data; deletion is not
secure erasure. `append` creates a missing file but refuses directory targets and
any result exceeding 4096 bytes before modifying the record.

`sleep` accepts an integer from 0 to 86400 seconds. In the kernel it uses the
existing monotonic clock and yields to the scheduler; it does not busy-wait for
the whole duration. Ctrl-C is processed when input resumes, not as a sleep signal.
`uptime` uses the kernel boot clock (Linux CLOCK_BOOTTIME in the development runner).

`shutdown` and `reboot` first flush the attached data backend and cancel on flush
failure. Native power control is qualified for QEMU's PIIX4/ICH9 chipsets: PCI
identification and PMBASE discovery precede S5/CF9 control. It does not claim a
generic ACPI AML interpreter or physical hardware qualification. The Linux runner
has no power callback, so these commands return an unavailable status there and
never power off/reboot the development workstation.

```sh
make -C boot ush-power-test
```

The power gate requires QMP guest RESET/SHUTDOWN events, a second kernel/prompt
after reboot, a successful shutdown process exit, and persistent file contents.

## Uedit

`uedit FILE` opens the [Uedit terminal editor](../uedit/README.md) on the mounted
UXFS volume. Existing files load into an owned buffer; new files are created on
Ctrl-S. Ctrl-Q warns before discarding dirty text, and background diagnostics
restore the document view/cursor. Uedit edits UTF-8/LF/CRLF/TAB
text up to 4096 bytes, with undo/redo, search/replace, selection/clipboard and a
resizable view. See its README for keys and terminal behavior. Host PTY tests and the
separate `make -C boot ush-uedit-test` gate cover editor/storage integration.

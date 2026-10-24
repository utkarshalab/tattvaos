# Uedit architecture

`inc/uedit.inc` defines the caller-owned 4152-byte document context: byte length
and cursor, viewport top/left, preferred visual column, retained CRLF style, dirty
flag, and 4096 bytes of document data. `src/core.asm` validates a load completely
before mutation. Positions always refer to valid scalar/CRLF boundaries. The
range-replacement primitive builds a bounded result before replacing document
bytes; public key editing encodes a scalar through the shared string library.

`src/text.asm` adapts `lib/str` checked UTF-8 encode/decode and generated Unicode
category/East Asian width tables to editor policy. It adds CRLF grouping, rejects
terminal control text, handles previous-boundary scans, and supplies scalar cell
width. The app links only the required library objects, not the whole library.
No copied UTF-8 implementation or private Unicode tables are maintained here.

`src/actions.asm` owns session history, saved baseline, selection anchor and owned
clipboard. History holds 64 full document/context snapshots (bounded to about
260 KiB); new edits truncate redo, evicting oldest entries if needed. Each range
edit records once. Restore recalculates dirty status against the saved bytes;
a new document remains dirty until saved. Literal search wraps once. Replacement
builds and checks all output in separate storage before one mutation/history step.
This bounded design fits the filesystem's existing 4 KiB document ceiling.

`src/terminal.asm` owns one serialized session and its prompts. `uedit_run(io,
bytes,length,label,new_file)` copies bytes before activation. The 32-byte callback
table contains read, write, save, optional size. All follow SysV AMD64 and preserve
callee-saved registers. Write consumes bytes synchronously; save copies bytes and
returns zero on success. Read returns a raw byte, -2 for resize/redraw, or another
negative result for EOF/error. Size receives two qword pointers with defaults.
The label remains readable for the session. Calls are not reentrant.

The renderer uses a bounded 64 KiB BSS frame, clips title/footer, highlights the
selection, expands tabs and never splits a displayed UTF-8 scalar at a viewport
edge. A document has rows-2 logical lines and columns-2 cells, with dimensions
capped to 240x100. Smaller than 20x4 displays a clipped resize notice. The cursor
is restored after every frame. Prompt input uses the same checked scalar encoder;
tabs appear as spaces in prompts while the query retains literal TAB bytes.
Basic VT CSI/SS3 keys and window size reports are decoded; unknown/modified
sequences are consumed as units. An invalid UTF-8 sequence pushes back a following
non-continuation byte so control keys retain their meaning.

The Ush adapter validates an interactive frontend, mounted volume and canonical
path, then supplies file data or an unsaved empty buffer. Its save callback
allocates only on save, copies bytes, zeros the unused file tail, and commits the
real UXFS snapshot. Failure retains editor text; mount failure/full capacity
cannot falsely clear dirty state. The optional frontend size callback is forwarded.
Linux handles SIGWINCH with a flag and -2 read event; UART accepts VT reports and
requests geometry at entry/Ctrl-L without waiting for a report.

Paired shell diagnostics route to Uedit while `uedit_active` is set, and restore
its view after the complete message. Only input-idle polls yield, keeping the
model stable on the BSP. Host signal cleanup restores the alternate screen and
termios without saving. The app links into the existing kernel bundle with RX
code and loader-owned BSS, without a new allocator, syscall layer or load address.
The largest nested editing path uses bounded stack buffers within the existing
16 KiB console fiber stack; document/history/frame storage lives in BSS.

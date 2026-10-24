# Uedit

Native NASM terminal text editor for TattvaOS. Open a document from Ush:

```text
ush> uedit /notes.txt
```

Uedit supports UTF-8 text, LF/CRLF line endings, undo/redo, literal search and
replacement, selection with an internal clipboard, and a resizable terminal view.
Files remain limited to the current UXFS maximum of **4096 bytes**. A missing file
opens an unsaved document and is created only by a successful save.

| Key | Action |
|---|---|
| Ctrl-S | Save to the mounted UXFS volume |
| Ctrl-Q | Quit; press twice to discard unsaved changes |
| Ctrl-Z / Ctrl-Y | Undo / redo (64 snapshots, up to 63 undo steps) |
| Ctrl-F, text, Enter | Literal, case-sensitive search, wrapping at EOF |
| Ctrl-N | Find next occurrence, wrapping at EOF |
| Ctrl-R, text, Enter | Enter replacement for the last search query |
| Ctrl-R / Ctrl-A in replacement confirmation | Replace one / all occurrences |
| Ctrl-C in a prompt | Cancel without changing the document |
| Ctrl-B, then movement | Set selection anchor; Ctrl-B again clears the mark |
| Ctrl-C / Ctrl-X / Ctrl-V | Copy selection / cut selection / paste internal clipboard |
| Ctrl-C without a selection | Cancel a quit warning; keep editing |
| Ctrl-L | Redraw and request UART terminal size |
| Arrows, Home/End, Ctrl-A/Ctrl-E | Move by scalar, logical line, or line start/end |
| Page Up/Down | Move by the current viewport height |
| Backspace / Delete / Ctrl-D | Delete previous / current scalar or newline |
| Enter / Tab | Insert the document's newline style / literal tab |

Typing, deletion or paste replaces an active selection. Selection is highlighted;
the clipboard belongs to the current editor session. Search and replacement
prompts accept up to 255 UTF-8 bytes; empty replacement deletes matches. Search
never edits the document. Replace-all checks the complete result before mutation,
so an oversized result leaves both document and undo history unchanged. Every
successful edit, cut, paste or replace operation is one undo step. Editing after
undo discards the redo branch; oldest snapshots are evicted when the history fills.
Undo/redo compares against the last successful save to determine the modified flag.

## Text and terminal behavior

UTF-8 is validated using `lib/str`'s checked decoder/encoder. Movement and deletion
respect Unicode scalar boundaries and treat CRLF as one newline. Existing line
endings, including mixed LF/CRLF files, are preserved byte-for-byte. Documents
loaded with any CRLF retain CRLF for new Enter keys even after deleting all their
newlines; new/LF-only documents use LF. Tabs display at four-column stops.

The renderer reuses `lib/str`'s complete Unicode category and East Asian width
tables: nonspacing/enclosing marks and format characters have zero width,
wide/fullwidth scalars two cells, others one. The terminal supplies glyphs and
shaping. Editing is by scalar, not grapheme cluster; complex emoji sequences,
Indic shaping and bidi layout can differ between terminals. No normalization or
case folding changes file bytes. NUL, standalone CR, C0 controls other than TAB/LF,
C1 controls, and malformed UTF-8 are rejected before loading. Bad keyboard sequences
are not inserted and do not swallow a following save/quit control key.

The Linux frontend handles SIGWINCH and redraws immediately from its size callback.
UART uses VT `CSI 18 t` queries and `CSI 8;rows;columns t` reports; Ctrl-L requests a
fresh size when the terminal does not report changes automatically. Without a size
callback/report it defaults to 80x24. The viewport adapts up to 240x100, keeping
larger terminals within those bounds. Below 20x4 a compact resize notice replaces
the document view; text and edits remain owned by the editor. Title/footer text is
clipped to prevent wrapping. Long documents and lines scroll without soft wrapping.
Escape is a VT sequence prefix; Ctrl-C cancels prompts and quit warnings.

## Build and use

From the repository root in Linux/WSL:

```sh
make -C apps/ush all
# Create once; the formatter refuses to overwrite an existing image.
python3 storage/uxfs/mkvolume.py apps/ush/build/data.uxfs
apps/ush/build/ush --disk apps/ush/build/data.uxfs
```

Run `uedit /notes.txt`, edit, Ctrl-S, Ctrl-Q. `cat /notes.txt` reads saved bytes.
The development runner requires an interactive terminal; piped and `ush -c`
invocations cannot enter Uedit.

```sh
make -C boot run UXFS_IMAGE=../apps/ush/build/data.uxfs
```

See the [UXFS contract](../../storage/uxfs/PERSISTENT_VOLUME.md) for explicit image
attachment and recovery. Uedit never formats a disk. `make -C apps/uedit` produces
`build/uedit-native.o`, a callable app without heap, libc, unresolved symbols or
host syscalls. Ush supplies terminal/storage callbacks. The shared library is a
Linux test artifact, not a new executable loader or process model.

## Save and failure behavior

Save preflights type, capacity and free records, copies owned bytes into UXFS and
commits its dual-bank snapshot. Only successful commit updates the saved baseline.
Failure retains the document and dirty state with `Save failed; changes retained`.
UXFS I/O failures disable the mount under its existing policy; no rollback is
promised after ambiguous flush failures. Undoing the last unsaved edit does not
create a new file; new documents remain unsaved until their first successful save.

Quit confirmation prevents accidental discard. Input closure and handled host
termination restore the primary screen without auto-saving. The Linux frontend
also restores termios. Paired kernel diagnostics use the footer row and redraw the
complete document/status/cursor on completion. Only UART input-idle polls yield;
editing, history and rendering stay serialized on the BSP. Fatal diagnostics
remain immediate.

## Verification

```sh
make -C apps/uedit test
make -C apps/uedit test-terminal
make -C apps/ush test
make -C boot ush-uedit-test
```

Native tests cover reference edits, UTF-8/CRLF boundaries, bounded history/redo
branches, selection/clipboard, atomic replacement, saved-state tracking, capacity,
invalid input, failure/discard/EOF and actual VT cells/cursor at several dimensions.
Real PTY tests inspect persistent bytes, resize without input, and verify termios
and screen restoration on exit and signals. QEMU uses two independent guests per
BIOS/SMP UEFI/strict-NX configuration and checks editing, UTF-8 search/replace,
clipboard/history, UART size reports, CRLF persistence and heartbeat redraw.
See [qualification evidence](QUALIFICATION.md) for the tested artifact and limits.

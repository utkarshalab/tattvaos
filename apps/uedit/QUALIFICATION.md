# Uedit qualification

The five-feature Uedit extension passed the checks below on 2026-10-24.
The native engine executes through a shared-library test artifact; PTY tests run
the real Ush frontend and persistent UXFS backend. No Python editor replaces the
NASM implementation. UTF-8 codec and Unicode tables are linked from `lib/str`.

## Host and native checks

- `make -C apps/ush test`: PASS, including the existing shell, calculator, file
  tools, native ABI, platform hooks and UXFS failure-injection gates.
- `make -C apps/uedit test`: PASS, including 15,000 reference edits and 350
  randomized literal replacements, Unicode/CRLF boundaries and cell widths,
  retained newline style, bounded undo/redo and branch truncation, saved-state
  dirty tracking, selection/cut/copy/paste, atomic capacity rejection, invalid
  input, save failures, discard/EOF, and intermediate VT frame bounds.
- Real PTY integration: PASS, including persistent Unicode/CRLF save/reopen,
  search/replace/history/clipboard, SIGWINCH redraw without a keypress, small and
  large terminals, invalid/full files, full-volume save failure, signal cleanup,
  screen restoration and termios restoration.
- Native and platform ABI binaries relinked against the final app: PASS.
- Bundle relocation/ownership and corrupt-metadata checks: PASS. The test fixture
  now derives section spacing from actual sizes, accommodating the UCD tables.
- Native unresolved-symbol checks: PASS (Uedit and Ush objects).

The final footer correction was checked against all intermediate frames. Its app
section extents, symbol addresses and generated NASM layout were proven identical
before refreshing the frozen bundle with kernel assembly paused. After linking,
all published app sections were compared byte-for-byte with a fresh link of the
current native object. The object hash also matches the frozen bundle manifest.

## Production QEMU gate

`make -C boot ush-uedit-test`: PASS on the production kernel in QEMU TCG,
`-cpu max`, 512 MiB RAM, with a separate temporary UXFS data image per configuration.
Each configuration runs two independent guests:

| Configuration | Create/edit guest | Fresh-guest verify |
|---|---|---|
| SeaBIOS, 1 CPU | PASS | PASS |
| OVMF, 4 CPUs | PASS | PASS |
| OVMF strict-NX, 1 CPU | PASS | PASS |

The first guest edits/saves multiline/tabbed text, restores the exact view and
mid-line cursor after a real heartbeat, and checks unsaved discard/cancel and
opening/discarding a missing file. It then exercises Unicode typing, undo/redo,
literal search/replace-all, selection/copy/paste and UART VT size reports. It opens
a seeded CRLF document, inserts a new CRLF line, and saves.

The second guest verifies saved content and edits the existing files again,
including Unicode replacement. After both guests, the host reads `/crlf` through
the real backend and requires exactly `line!\r\nnext\r\n`. Both guests also run
the existing shell editing/chaining, calculator, uptime, cooperative sleep,
VT clear, error/prompt recovery and scheduler-after-exit checks. BIOS checks that
the primary boot-image hash remains unchanged. No fatal diagnostics were present.

UART transcripts are `apps/ush/build/qemu-*-uedit-{create,verify}.log` with matching
stderr files. The full gate output is `/tmp/uedit-five-qemu.log` in the WSL
validation environment. These are focused emulator checks; physical hardware and
the entire broad boot regression matrix are not qualified by this gate.

## Artifact

- Kernel file: 9,990,928 bytes
- Executable prefix: 405,504 bytes
- Owned memory extent: 52,852,864 bytes
- Boot image: 10,024,448 bytes (19,579 sectors)
- Kernel SHA-256: `63c376cc1a1824dff8460948dba50b9dbc8ff96acf85c5d9fc26a5896272bbb4`
- App sections: text 41,472; rodata 81,024; data 3,008; BSS 1,100,608 bytes

This identifies the tested integration artifact, not a permanent release. Image
layout/ULF integrity and kernel section hygiene passed, and Make reports the image
current. The app's instructions are in the executable prefix; Unicode tables and
document/history/frame state are covered by loader-owned initialized/BSS extents.
There are no remaining NASM or QEMU processes from this validation.

The UXFS file ceiling remains 4096 bytes. UTF-8 editing uses scalar boundaries;
terminal shaping, grapheme clusters, complex emoji and bidi layout are not fully
modeled. The [README](README.md) documents keys, capacities and resize behavior.

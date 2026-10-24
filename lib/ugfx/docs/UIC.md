# UIC — Utkarsha icon format, version 1

UIC stores vector icons for drawing at any size. One file (a *pack*) holds
any number of icons, each looked up by name. Icons are authored as SVG and
converted to UIC when the system is built; UIC is the run-time form only.

All numbers are little-endian. Offsets are in bytes.

## File

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | magic `55 49 43 1A` (`"UIC"`, 0x1A) |
| 4 | 2 | version, 1 |
| 6 | 2 | flags, 0 |
| 8 | 4 | icon count *n* |
| 12 | 4 | index offset (from the start of the file, a multiple of 4) |
| 16 | 4 | string table offset |
| 20 | 4 | string table size |
| 24 | 4 | data offset (icon bodies) |
| 28 | 4 | data size |

The index, string table and data must each lie inside the file.

### Index

*n* entries of 16 bytes:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | name offset in the string table |
| 4 | 4 | body offset in the data |
| 8 | 4 | body size |
| 12 | 2 | name length (1 or more bytes, no terminator) |
| 14 | 2 | design size in pixels; 0 = scalable |

Entries are sorted, strictly increasing, by name (bytes compared
unsigned; a prefix sorts first) and then by design size. One name may have
several entries: a scalable one and pixel-tuned ones for small sizes.

Looking up a name at a pixel size picks, among that name's entries: for
size 0, the scalable entry (the largest design size if there is none);
otherwise the smallest non-zero design size at
or above the request, else the scalable entry, else the largest design
size.

## Icon body

| Offset | Size | Field |
|---|---|---|
| 0 | 16 | viewBox x, y, width, height (f32; width and height > 0) |
| 16 | 1 | fraction bits *f* (0–14) |
| 17 | 1 | colour slot count *s* (1–16) |
| 18 | 2 | reserved, 0 |
| 20 | 4 × *s* | default colour of each slot (straight BGRA, 0xAARRGGBB) |
| 20 + 4*s* | … | commands, up to and including END |

Coordinates are signed 16-bit integers *q* meaning *q* / 2^*f* viewBox
units. The converter picks *f* as large as the icon's coordinates allow,
so precision is 1/256 of a unit on a 24-unit grid, 1/32 on a 512-unit grid.

Slot 0 is the icon's main colour (SVG `currentColor`); drawing can replace
any slot's colour. Duotone icons use slot 1 with an OPACITY command.

### Commands

Each command is an opcode byte and its operands.

| Opcode | Command | Operands |
|---|---|---|
| 0x00 | END | — |
| 0x01 | MOVE | x, y (i16) |
| 0x02 | LINE | x, y |
| 0x03 | QUAD | x1, y1, x, y |
| 0x04 | CUBIC | x1, y1, x2, y2, x, y |
| 0x05 | CLOSE | — |
| 0x10 | FILL | slot (u8), rule (u8: 0 nonzero, 1 even-odd) |
| 0x11 | STROKE | slot (u8), join \| cap << 4 (u8: join 0 miter, 1 round, 2 bevel; cap 0 butt, 1 round, 2 square), width (i16 coordinate units, > 0) |
| 0x20 | OPACITY | alpha (u8), for the commands after it |

MOVE … CLOSE build the current path; FILL and STROKE draw it and start an
empty one. Strokes use miter limit 4. Their widths are multiplied by the
stroke weight given when drawing (1 = as designed), which gives thin,
regular and bold variants from one icon.

A body must end with END inside its size. Opening a pack checks the
header, the index (bounds, order) and every body (opcodes, operand bounds,
slots, rules, joins, caps, widths), so a pack from anywhere is safe to
draw.

## Drawing

`ugfx_uic_draw(uic, icon, ctx, colours, count, x, y, size, weight)` fits
the viewBox into the square (x, y, size, size) of the context's user
space, keeping its aspect ratio and centring it, and draws the commands
through the context (its transform, clip, global alpha and layers all
apply). `colours` (straight BGRA) overrides the first
`count` slots.

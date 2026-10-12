# Fuzz Corpus — Seed Inputs Per Target

Add minimal valid seeds per target directory:

- `wire/` — one valid message per opcode class
- `objects/` — handle create/resolve/destroy sequences
- `keymap/` — one valid `.km` file
- `config/` — one valid config per file type
- `png/` — 1x1 valid PNG (see `tests/golden/data/sample.png` when added)
- `jpeg/` — minimal JFIF baseline
- `gif/` — minimal GIF89a
- `ttf/` — minimal TrueType with `cmap`+`glyf`
- `icc/` — minimal ICC with rXYZ + rTRC
- `rfb/` — version + ServerInit byte prefix

Every new parser lands with at least one seed. Fuzzers never commit
crashing inputs — they file them as regression tests instead.

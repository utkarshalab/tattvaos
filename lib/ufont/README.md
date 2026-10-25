# lib/ufont — Font Library

The **`lib/ufont`** library is the font library of Utkarsha OS: reading font
files, choosing a face for a family, weight and style, and handing out
glyph outlines and metrics. The Canvas display server draws SVG text with
it; the web engine, terminals and document viewers are meant to use the
same library rather than each carrying a font reader.

ufont does not rasterize. Outlines go into [`lib/ugfx`](../ugfx/) paths,
so text is filled, transformed, clipped and anti-aliased like any other
drawing. Text shaping will use the Unicode data in [`lib/str`](../str/)
(scripts, Devanagari clusters, joining classes).

---

## 1. Layout

```
lib/ufont/
├── include/
│   └── ufont.inc         ← layouts: UfontFont, UfontSet / UfontFace, UfontStd
├── sfnt/
│   └── sfnt.asm          ← TrueType reading: tables, cmap, advances, metrics, outlines
├── match/
│   └── fontset.asm       ← font sets: CSS family lists, weight / style; ugfx's font callback
├── fonts/                ← the shipped fonts (Noto, Liberation), their licences, README.md
├── tools/
│   └── fontmodel.py      ← the library modelled over fontTools (development machine)
└── tests/host/
    ├── host_font.asm     ← host tool: glyphs, metrics, matching
    └── font_check.py     ← checks host_font against fontmodel
```

Programs assemble the sources into their own builds (Canvas does through
`UFONT_DIR`, as it does for ugfx); they provide `arena_alloc` and link
ugfx's path code. Include paths: `lib/ufont/include` and `lib/ugfx/include`.

---

## 2. Interface

### Fonts (sfnt/sfnt.asm)

| Call | Does |
|---|---|
| `ufont_open(arena, data, length)` | index a TrueType font (the bytes stay the caller's) → `UfontFont*` or 0 |
| `ufont_glyph(font, code point)` | the glyph for a character → glyph id, 0 when the font has none |
| `ufont_advance(font, glyph)` | its advance width in font units |
| `ufont_metrics(font)` | units per em, ascent, descent (font units) |
| `ufont_outline(font, glyph, path, scale, arena)` | its outline into a ugfx path at `scale` pixels per font unit, y down, origin on the baseline → 0, -EINVAL, -ENOMEM |

What is read: the table directory and head, maxp, hhea, hmtx, loca, glyf
and cmap, every offset and length checked against the data first; cmap
format 12 (preferred) or 4 on a Unicode encoding; simple glyphs (flag
repeats, short and long coordinates, implied on-curve points between
off-curve ones) and composite glyphs (offsets, a scale, x and y scales or
a 2 x 2 matrix, scaled offsets when flagged; point-matched components at
offset 0), six levels deep at most, 16384 points per glyph at most. Not
read: hinting instructions, kerning, OpenType layout, CFF outlines,
variations, colour glyphs.

### Font sets (match/fontset.asm)

| Call | Does |
|---|---|
| `ufont_set_init(set, arena)` | an empty set (`UfontSet_SIZE` bytes, up to 32 faces) |
| `ufont_set_add(set, data, length, family, weight, italic)` | open a font and add it under a family name → 0, -EINVAL, -ENOMEM |
| `ufont_set_face(set, UgfxSvgFont*)` | the face for a CSS `font-family` list, weight and style → `UfontFace*` |
| `ufont_svg_font` | lib/ugfx's SVG font callback (`UgfxSvg_font_fn`, user = the set): advances, outlines, ascent / descent |
| `ufont_standard`, `ufont_standard_count` | the shipped fonts: file name, family, weight, italic (`UfontStd`) |

Matching: the family list is read as CSS has it (comma separated, quoted
or not, without case). Generic and common names stand for the shipped
families — `sans-serif`, `system-ui`, `ui-sans-serif`, `cursive`, `fantasy`:
Noto Sans; `serif`, `ui-serif`: Noto Serif; `monospace`, `ui-monospace`:
Noto Sans Mono; Arial, Helvetica, Helvetica Neue, Arimo: Liberation Sans;
Times New Roman, Times, Tinos: Liberation Serif; Courier New, Courier,
Cousine: Liberation Mono. The first name with a face in the set wins,
else Noto Sans, else the first face. Within a family the style is matched
first, then the weight (bold from 600). A character the face lacks comes
from Noto Sans in the same style.

Loading: a program maps each `ufont_standard` file from the fonts
directory — installed read-only at `/app/lib/ufont/fonts/` — and adds it
with its family, weight and style; the set then serves any number of
documents. Canvas hands its set to `svg_set_fonts`.

---

## 3. Fonts

`fonts/` holds Noto Sans, Noto Serif and Noto Sans Mono (subset to Latin,
Greek and Cyrillic with common symbols) and Liberation Sans, Serif and
Mono (unmodified, for documents naming Arial / Helvetica, Times New Roman
and Courier New, whose character widths they share). Sources, the exact
subsetting command and the licences (SIL OFL 1.1): `fonts/README.md`.

---

## 4. Tests

`make host-check` (needs nasm, ld, python3 with fontTools) builds
`host_font` and runs `tests/host/font_check.py`:

- every code point each shipped font maps, and some it does not: the glyph,
  the advance and the outline's verbs and points identical to fontTools'
  reading through `tools/fontmodel.py`;
- the metrics;
- 567 matching queries (family lists with generic names, aliases, quotes,
  case and unknown names, weights 100 to 900, normal / italic / oblique);
- truncated and corrupted fonts never crash the reader.

Canvas's `tests/host/svg_text_check.py` checks the whole path: SVG text
decoded by Canvas with these fonts, identical to ugfx drawing the model's
calls.

---

## 5. Next

- A glyph outline cache, so repeated characters are not decoded again.
- Text shaping (OpenType GSUB / GPOS) — Devanagari first, then the other
  Indic scripts and Arabic — with lib/str's Unicode data; the matching
  Noto families join the shipped fonts then.
- Kerning for scripts that need no shaping.
- CFF outlines, WOFF / WOFF2, font collections; variable fonts.

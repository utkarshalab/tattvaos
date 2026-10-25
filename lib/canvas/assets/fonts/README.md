# Canvas fonts

The fonts Canvas ships, read by `src/font/sfnt.asm` and chosen by
`src/font/fontset.asm` (its `fontset_standard` table lists these files with
their family, weight and style). They install read-only to
`/app/lib/canvas/fonts/`; whoever starts Canvas loads them into a font set
(`fontset_init`, `fontset_add`) and hands it to `svg_set_fonts`.

| Family | Files | Licence |
|---|---|---|
| Noto Sans | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `OFL-Noto.txt` |
| Noto Serif | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `OFL-Noto.txt` |
| Noto Sans Mono | Regular, Bold | SIL OFL 1.1 — `OFL-Noto.txt` |
| Liberation Sans | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `LICENSE-Liberation.txt` |
| Liberation Serif | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `LICENSE-Liberation.txt` |
| Liberation Mono | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `LICENSE-Liberation.txt` |

Noto is the default for everything: no family, `sans-serif`, `serif`,
`monospace` and the `ui-*` / `system-ui` names. Liberation has the same
character widths as Arial / Helvetica, Times New Roman and Courier New, so
documents that name those lay out as their authors measured them; those
names (and Arimo, Tinos, Cousine) map to it.

## Where they come from

- Noto: notofonts/latin-greek-cyrillic releases NotoSans-v2.015,
  NotoSerif-v2.015 and NotoSansMono-v2.014, the `unhinted/ttf` static
  files. Subset with fontTools to Latin (with Extended-A/B and Additional),
  IPA and spacing modifiers, combining marks, Greek (with Extended),
  Cyrillic (with Supplement), punctuation, currency, letterlike symbols,
  arrows, mathematical operators, enclosed numbers, geometric shapes and
  the Latin ligatures; hinting and layout tables dropped (Canvas does not
  run either):

  ```
  python3 -m fontTools.subset <file> --unicodes=U+0020-007E,U+00A0-024F,U+0259,U+02B0-02FF,U+0300-036F,U+0370-03FF,U+0400-052F,U+1E00-1EFF,U+1F00-1FFF,U+2000-206F,U+20A0-20C0,U+2100-214F,U+2190-21FF,U+2200-22FF,U+2460-24FF,U+25A0-25FF,U+FB00-FB06,U+FFFD --layout-features='' --no-hinting --drop-tables+=GSUB,GPOS,GDEF,DSIG --name-IDs='*' --notdef-outline
  ```

  The Noto licence names no Reserved Font Name, so subset files keep their
  names.
- Liberation: liberationfonts/liberation-fonts 2.1.5
  (`liberation-fonts-ttf-2.1.5.tar.gz`), unmodified. "Liberation" is a
  Reserved Font Name under its licence, so these files are not subset.

## What is not covered yet

Scripts that need shaping (Devanagari and the other Indic scripts, Arabic)
wait for text shaping (docs/ROADMAP.md TXT-04 / TXT-05); their Noto
families join the set then. Colour emoji need colour glyph tables, which
`sfnt.asm` does not read. A character no shipped face has draws as the
face's missing-glyph box.

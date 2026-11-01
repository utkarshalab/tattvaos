# lib/ufont fonts

The fonts lib/ufont ships, read by `sfnt/sfnt.asm` and chosen by
`match/fontset.asm`. `match/standard.asm` (generated from these files by
`tools/fonts_table.py`) lists every face with its family, weight, style,
collection index and coverage. They install read-only to
`/app/lib/ufont/fonts/`; a program puts them in a font set with
`ufont_set_standard` (each file mapped by the program's loader the first
time the set needs that face - text in a script opens only its font) or
loads its own with `ufont_set_add` — Canvas then hands its set to
`svg_set_fonts`.

English (Latin) text uses Noto Sans and the families below it in the
table; every other script has its Noto font, chosen by fallback for the
characters the asked-for face lacks.

| Family | Files | Licence |
|---|---|---|
| Noto Sans | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `OFL-Noto.txt` |
| Noto Serif | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `OFL-Noto.txt` |
| Noto Sans Mono | Regular, Bold | SIL OFL 1.1 — `OFL-Noto.txt` |
| Liberation Sans | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `LICENSE-Liberation.txt` |
| Liberation Serif | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `LICENSE-Liberation.txt` |
| Liberation Mono | Regular, Bold, Italic, BoldItalic | SIL OFL 1.1 — `LICENSE-Liberation.txt` |
| Noto Sans Devanagari | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Devanagari.txt` |
| Noto Serif Devanagari | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Devanagari.txt` |
| Noto Sans Bengali | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Gurmukhi | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Gujarati | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Oriya | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Tamil | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Telugu | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Kannada | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Malayalam | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Indic.txt` |
| Noto Sans Arabic | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Arabic-Hebrew.txt` |
| Noto Naskh Arabic | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Arabic-Hebrew.txt` |
| Noto Sans Hebrew | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Arabic-Hebrew.txt` |
| Noto Serif Hebrew | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Arabic-Hebrew.txt` |
| Noto Sans CJK SC, TC, HK, JP, KR and Noto Sans Mono CJK (the same five) | Regular, Bold (`NotoSansCJK-Regular.ttc`, `NotoSansCJK-Bold.ttc`: ten faces each) | SIL OFL 1.1 — `LICENSE-Noto-CJK.txt` |
| The other scripts, Regular and Bold: Noto Nastaliq Urdu, Noto Sans Adlam, Noto Sans Armenian, Noto Sans Balinese, Noto Sans Bamum, Noto Sans Bassa Vah, Noto Sans Canadian Aboriginal, Noto Sans Cham, Noto Sans Cherokee, Noto Sans Duployan, Noto Sans Ethiopic, Noto Sans Georgian, Noto Sans Gunjala Gondi, Noto Sans Hanifi Rohingya, Noto Sans Javanese, Noto Sans Kawi, Noto Sans Kayah Li, Noto Sans Khmer, Noto Sans Lao, Noto Sans Lisu, Noto Sans Medefaidrin, Noto Sans Meetei Mayek, Noto Sans Myanmar, Noto Sans Nag Mundari, Noto Sans New Tai Lue, Noto Sans Ol Chiki, Noto Sans Sinhala, Noto Sans Sora Sompeng, Noto Sans Sundanese, Noto Sans Symbols, Noto Sans Tai Tham, Noto Sans Tangsa, Noto Sans Thaana, Noto Sans Thai, Noto Sans Vithkuqi, Noto Serif Hentaigana, Noto Serif NP Hmong, Noto Serif Tibetan, Noto Serif Toto, Noto Serif Yezidi | Regular, Bold | SIL OFL 1.1 — `OFL-Noto-Scripts.txt` |
| The other scripts, Regular only: Noto Music, Noto Sans Anatolian Hieroglyphs, Noto Sans Avestan, Noto Sans Batak, Noto Sans Bhaiksuki, Noto Sans Brahmi, Noto Sans Buginese, Noto Sans Buhid, Noto Sans Carian, Noto Sans Caucasian Albanian, Noto Sans Chakma, Noto Sans Chorasmian, Noto Sans Coptic, Noto Sans Cuneiform, Noto Sans Cypriot, Noto Sans Cypro Minoan, Noto Sans Deseret, Noto Sans Egyptian Hieroglyphs, Noto Sans Elbasan, Noto Sans Elymaic, Noto Sans Glagolitic, Noto Sans Gothic, Noto Sans Grantha, Noto Sans Hanunoo, Noto Sans Hatran, Noto Sans Imperial Aramaic, Noto Sans Indic Siyaq Numbers, Noto Sans Inscriptional Pahlavi, Noto Sans Inscriptional Parthian, Noto Sans Kaithi, Noto Sans Kharoshthi, Noto Sans Khojki, Noto Sans Khudawadi, Noto Sans Lepcha, Noto Sans Limbu, Noto Sans Linear A, Noto Sans Linear B, Noto Sans Lycian, Noto Sans Lydian, Noto Sans Mahajani, Noto Sans Mandaic, Noto Sans Manichaean, Noto Sans Marchen, Noto Sans Masaram Gondi, Noto Sans Math, Noto Sans Mayan Numerals, Noto Sans Mende Kikakui, Noto Sans Meroitic, Noto Sans Miao, Noto Sans Modi, Noto Sans Mongolian, Noto Sans Mro, Noto Sans Multani, Noto Sans NKo, Noto Sans Nabataean, Noto Sans Nandinagari, Noto Sans Newa, Noto Sans Nushu, Noto Sans Ogham, Noto Sans Old Hungarian, Noto Sans Old Italic, Noto Sans Old North Arabian, Noto Sans Old Permic, Noto Sans Old Persian, Noto Sans Old Sogdian, Noto Sans Old South Arabian, Noto Sans Old Turkic, Noto Sans Osage, Noto Sans Osmanya, Noto Sans Pahawh Hmong, Noto Sans Palmyrene, Noto Sans Pau Cin Hau, Noto Sans PhagsPa, Noto Sans Phoenician, Noto Sans Psalter Pahlavi, Noto Sans Rejang, Noto Sans Runic, Noto Sans Samaritan, Noto Sans Saurashtra, Noto Sans Sharada, Noto Sans Shavian, Noto Sans Siddham, Noto Sans SignWriting, Noto Sans Sogdian, Noto Sans Soyombo, Noto Sans Sunuwar, Noto Sans Syloti Nagri, Noto Sans Symbols 2, Noto Sans Syriac, Noto Sans Tagalog, Noto Sans Tagbanwa, Noto Sans Tai Le, Noto Sans Tai Viet, Noto Sans Takri, Noto Sans Tamil Supplement, Noto Sans Tifinagh, Noto Sans Tirhuta, Noto Sans Ugaritic, Noto Sans Vai, Noto Sans Wancho, Noto Sans Warang Citi, Noto Sans Yi, Noto Sans Zanabazar Square, Noto Serif Ahom, Noto Serif Dives Akuru, Noto Serif Dogra, Noto Serif Khitan Small Script, Noto Serif Makasar, Noto Serif Old Uyghur, Noto Serif Ottoman Siyaq, Noto Serif Tangut, Noto Serif Todhri | Regular | SIL OFL 1.1 — `OFL-Noto-Scripts.txt` |

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
  the Latin ligatures; hinting dropped (nothing runs it), the layout tables
  (GDEF, GSUB, GPOS: ligatures, contextual forms, kerning, mark
  placement) kept for text shaping:

  ```
  python3 -m fontTools.subset <file> --unicodes=U+0020-007E,U+00A0-024F,U+0259,U+02B0-02FF,U+0300-036F,U+0370-03FF,U+0400-052F,U+1E00-1EFF,U+1F00-1FFF,U+2000-206F,U+20A0-20C0,U+2100-214F,U+2190-21FF,U+2200-22FF,U+2460-24FF,U+25A0-25FF,U+FB00-FB06,U+FFFD --layout-features='*' --no-hinting --drop-tables+=DSIG --name-IDs='*' --notdef-outline
  ```

  The Noto licence names no Reserved Font Name, so subset files keep their
  names.
- Noto Devanagari: notofonts/devanagari releases NotoSansDevanagari-v2.007
  and NotoSerifDevanagari-v2.006, the `unhinted/ttf` static Regular and
  Bold, unmodified (they cover Devanagari, Vedic Extensions, Devanagari
  Extended, the dotted circle and basic Latin).
- Noto Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada,
  Malayalam: the notofonts/<script> releases
  NotoSansBengali-v3.011
  NotoSansGurmukhi-v2.004
  NotoSansGujarati-v2.106
  NotoSansOriya-v2.007
  NotoSansTamil-v2.004
  NotoSansTelugu-v2.005
  NotoSansKannada-v2.006
  NotoSansMalayalam-v2.104
  - the `unhinted/ttf` static Regular and Bold, unmodified.
- Noto Arabic and Hebrew: the notofonts/arabic releases
  NotoSansArabic-v2.013 and NotoNaskhArabic-v2.021 and the
  notofonts/hebrew releases NotoSansHebrew-v3.001 and
  NotoSerifHebrew-v2.004, the `unhinted/ttf` static Regular and Bold,
  unmodified.
- The other scripts: notofonts.github.io's `fonts/<family>/unhinted/ttf/`
  Regular and Bold (where there is a Bold), main as of 2026-10-31,
  unmodified: one Noto Sans family per script, a Noto Serif one where the
  script has no Sans (Ahom, Dives Akuru, Dogra, Hentaigana, Khitan Small
  Script, Makasar, Nyiakeng Puachue Hmong, Old Uyghur, Ottoman Siyaq,
  Tangut, Tibetan, Todhri, Toto, Yezidi), Noto Nastaliq Urdu, Noto Sans
  Math, Symbols, Symbols 2 and Noto Music. Left out: the UI, Looped,
  Unjoined, Display and test variants, Kufi and Rashi, the Syriac Eastern /
  Western forms, Znamenny and Traditional Nushu.
- Noto Sans CJK: notofonts/noto-cjk `Sans/OTC/NotoSansCJK-Regular.ttc` and
  `NotoSansCJK-Bold.ttc` (version 2.004), unmodified. Fallback takes the
  Simplified Chinese face for Han (no language yet picks the region); all
  ten faces have Hangul and kana.
- Liberation: liberationfonts/liberation-fonts 2.1.5
  (`liberation-fonts-ttf-2.1.5.tar.gz`), unmodified. "Liberation" is a
  Reserved Font Name under its licence, so these files are not subset.

## What is not covered yet

Every script's face is in `ufont_standard` under its family name ("Noto
Sans Devanagari", "Noto Sans Thai", "Noto Sans CJK JP" and so on); text
in a script in any other family falls back to it (Arabic to Noto Sans
Arabic first, Hebrew to Noto Sans Hebrew) and is shaped by the script's
shaper. Han text takes the Simplified Chinese forms whatever its language
(choosing the region by language is to come). Colour emoji need colour
glyph tables, which `sfnt.asm` does not read. A character no shipped face
has draws as the face's missing-glyph box.

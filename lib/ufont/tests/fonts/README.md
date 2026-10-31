# lib/ufont test fonts

Fonts the host checks use beyond the shipped ones (development machine
only; not installed).

| File | What | Licence |
|---|---|---|
| NotoSans-VF-test.ttf | Noto Sans variable (wdth, wght), subset to Basic Latin, Latin-1 letters, a few marks | SIL OFL 1.1 — `OFL-Noto.txt` |
| NotoSansArabic-VF-test.ttf | Noto Sans Arabic variable (wdth, wght), subset to Arabic and its presentation forms | SIL OFL 1.1 — `OFL-Noto.txt` |
| NotoSansDevanagari-VF-test.ttf | Noto Sans Devanagari variable (wdth, wght), subset to Devanagari and Basic Latin | SIL OFL 1.1 — `OFL-Noto.txt` |
| NotoSansThai-Regular.ttf | Noto Sans Thai (shape_check: the Thai shaper, and made an old PUA font) | SIL OFL 1.1 — `OFL-Noto.txt` |
| NotoSansLao-Regular.ttf | Noto Sans Lao (shape_check: the Thai shaper for Lao) | SIL OFL 1.1 — `OFL-Noto.txt` |
| NotoSansKR-Regular.otf | Noto Sans KR (CFF), subset to ASCII, the jamo blocks, tone marks, U+25CC and U+AC00..B2E3 (shape_check: the Hangul shaper; syllables past the subset are decomposed) | SIL OFL 1.1 — `OFL-Noto.txt` |

The `-Regular.ttf` fonts are notofonts.github.io's
`fonts/<family>/unhinted/ttf/<family>-Regular.ttf` as published; shape_check
shapes each with text in its script. NotoSansKR-Regular.otf is noto-cjk's
`Sans/SubsetOTF/KR/NotoSansKR-Regular.otf`, subset:

```
python3 -m fontTools.subset NotoSansKR-Regular.otf --layout-features='*' --no-hinting \
    --unicodes='U+0020-007E,U+1100-11FF,U+3131-318E,U+302E-302F,U+25CC,U+A960-A97F,U+D7B0-D7FF,U+AC00-B2E3,U+D55C,U+AE00,U+C548,U+B155'
```

The variable ones come from notofonts.github.io's `fonts/<family>/unhinted/variable-ttf`
files (NotoSans[wdth,wght].ttf and the Arabic and Devanagari ones),
subset with fontTools keeping every layout feature and the variation
tables (fvar, avar, gvar, HVAR, GDEF's variation store):

```
python3 -m fontTools.subset <file> --unicodes=<ranges> --layout-features='*' --no-hinting
```

The Noto licence names no Reserved Font Name, so subset files may be
renamed.

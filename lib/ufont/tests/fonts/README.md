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

The `-Regular.ttf` fonts are notofonts.github.io's
`fonts/<family>/unhinted/ttf/<family>-Regular.ttf` as published; shape_check
shapes each with text in its script. The variable ones come from notofonts.github.io's `fonts/<family>/unhinted/variable-ttf`
files (NotoSans[wdth,wght].ttf and the Arabic and Devanagari ones),
subset with fontTools keeping every layout feature and the variation
tables (fvar, avar, gvar, HVAR, GDEF's variation store):

```
python3 -m fontTools.subset <file> --unicodes=<ranges> --layout-features='*' --no-hinting
```

The Noto licence names no Reserved Font Name, so subset files may be
renamed.

# Canvas UI font

The one font canvasd carries for the text it draws itself: the greeter's
label, taskbar titles and title bars (`src/text/ui_text.asm` embeds it).

| File | What | Licence |
|---|---|---|
| NotoSans-UI.ttf | Noto Sans Regular, subset to Basic Latin, Latin-1, U+2022 (bullet) and U+2026 (ellipsis), with kerning and ligatures | SIL OFL 1.1 — `OFL-Noto.txt` |

Made from `lib/ufont/fonts/NotoSans-Regular.ttf` with fontTools, on the
development machine:

```
python3 -m fontTools.subset ../ufont/fonts/NotoSans-Regular.ttf \
    --unicodes='U+0020-007E,U+00A0-00FF,U+2022,U+2026' \
    --layout-features='kern,liga' --no-hinting \
    --output-file=assets/fonts/NotoSans-UI.ttf
```

Noto's licence reserves no font names, so a subset may keep its name.
Text in other scripts waits for the full shipped fonts, which load once
there is a file system.

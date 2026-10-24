# Canvas UI icons

`ui/*.svg` are 28 icons from [Lucide](https://lucide.dev) (ISC licence,
[`LICENSE-lucide.txt`](LICENSE-lucide.txt)), taken unchanged from
`lucide-icons/lucide` at commit `7faf87628a1ad6175975bc595344337ce14a7db4`,
the commit pinned in `lib/ugfx/icons/sources.json`.

`ui.uic` is those icons as a UIC pack (`lib/ugfx/docs/UIC.md`), built with
`lib/ugfx/tools/svg2uic.py`. It is embedded in Canvas (`src/shell/icons.asm`)
for window decorations and other server-drawn UI, so Canvas has icons without
loading files. It is generated, but kept here so that building Canvas needs
only NASM; after changing `ui/`, run `make ui-icons` to rebuild it.

| Use | Icons |
|---|---|
| Window controls | `x`, `minus`, `square`, `copy`, `maximize`, `minimize`, `menu` |
| Navigation | `chevron-up`, `chevron-down`, `chevron-left`, `chevron-right`, `house` |
| Actions | `check`, `plus`, `search`, `settings`, `pencil`, `power` |
| Status | `bell`, `volume-2`, `wifi`, `battery`, `lock`, `user`, `info`, `circle-alert` |
| Files | `folder`, `file` |

# Canvas Admin Guide (C33) — Deployment, Config, Profiles, Seats, Kiosk

## Files

| File | Purpose |
|------|---------|
| `conf/canvas.conf` | server settings (backend, policy, log level) |
| `conf/outputs.conf` | output layout, scale, rotation |
| `conf/seats.conf` | seat → device mapping |
| `conf/policy.conf` | window policy selection + options |
| `conf/rules.conf` | per-app window rules |
| `conf/profiles/*.profile` | trust profiles (trusted/standard/sandboxed/remote/kiosk) |
| `conf/keymaps/*.km` | keyboard layouts |

## Deployment Modes

- **Desktop**: `fb_linear` or `native` backend, floating or tiling policy.
- **Headless/server**: `headless` + `remote` backends, RFB/CRP viewers.
- **Kiosk**: kiosk policy + kiosk trust profile, single allowed app, watchdog on.
- **Enterprise**: multi-seat via `seats.conf`, audit log shipped off-box.

## Seats

Map input devices and outputs per seat in `seats.conf`. Each seat gets its
own focus, cursor, keymap, and session. Hotplug re-evaluates the mapping.

## Kiosk

1. Set `policy=kiosk`, `allowed_app_id=<id>` in `policy.conf`.
2. Assign the `kiosk` trust profile to the launcher.
3. Verify: killing the app restarts it; no other window can appear;
   `canvasctl` shows exactly one toplevel.

## Troubleshooting

- `canvasctl` — live clients, scene dump, trace control.
- `canvas-record`/`canvas-replay` — capture a failing session, replay it.
- `faultdump` via `cw_debug` — last fault with registers + recent trace.
- Audit log — who was granted what, and when.

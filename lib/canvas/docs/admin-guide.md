# Canvas Admin Guide (C33) — Deployment, Config, Profiles, Seats, Kiosk

## Files

| File | Purpose |
|------|---------|
| `conf/apps/canvas/canvas.conf` | server settings: see below |
| `conf/outputs.conf` | output layout, scale, rotation |
| `conf/seats.conf` | seat → device mapping |
| `conf/policy.conf` | window policy selection + options |
| `conf/rules.conf` | per-app window rules |
| `conf/profiles/*.profile` | trust profiles (trusted/standard/sandboxed/remote/kiosk) |
| `conf/keymaps/*.km` | keyboard layouts |

## canvas.conf

Read once when `canvasd` starts. Without the file the defaults below stand.

```
# a comment; so is a line starting with ;
[log]
level = info            # error, warn, info, debug or trace

[input]
repeat_delay = 500      # ms before a held key repeats: 100 to 2000
repeat_rate = 30        # repeats a second: 0 (none) to 100

[session]
lock_after = 300        # seconds without input before the screen locks:
                        # 0 (never) to 86400

[display]
high_contrast = false   # true or false (also yes / no, on / off, 1 / 0)

[power]
lid_close = sleep       # sleep, or lock: the lid closed with no other
                        # screen on
```

| Section | Key | Values | Default |
|---------|-----|--------|---------|
| `log` | `level` | `error`, `warn`, `info`, `debug`, `trace` | `info` |
| `input` | `repeat_delay` | 100 to 2000 (ms) | 500 |
| `input` | `repeat_rate` | 0 to 100 a second, 0 no repeat | 30 |
| `session` | `lock_after` | 0 to 86400 (s), 0 never | 300 |
| `display` | `high_contrast` | `true` / `false` | `false` |
| `power` | `lid_close` | `sleep`, `lock` | `sleep` |

The format: `[section]` headers; `key = value` lines; `#` or `;` starting a
comment, at a line's start or after a space; strings bare or in double
quotes, with `\"`, `\\`, `\n` and `\t`. Every value is checked against its key. A
line with a mistake (bad syntax, an unknown section or key, a value of the
wrong kind or out of range, a key given twice) is not taken, and the log
says which line and why and how many there were; every other line is
applied, so one mistake costs only its own line. The keys under an unknown
section are passed over with it.

A user's own settings (`/user/<name>/conf/canvas/canvas.conf`) are read
once the login says who they are; not yet.

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

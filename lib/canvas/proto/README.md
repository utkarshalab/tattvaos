# CWP Protocol Definitions

Source of truth for Canvas Wire Protocol. Each `.cwp` file defines one protocol extension.

## Files

| File | Interfaces | Phase |
|------|------------|-------|
| `canvas-core.cwp` | `cw_display`, `cw_caps`, `cw_buffer`, `cw_fence`, `cw_timeline`, `cw_surface`, `cw_subsurface` | C4 |
| `canvas-present.cwp` | `cw_present` | C8 |
| `canvas-output.cwp` | `cw_output` | C11 |
| `canvas-input.cwp` | `cw_seat`, `cw_pointer`, `w_keyboard`, `cw_touch`, `cw_tablet` | C12 |
| `canvas-shell.cwp` | `cw_shell`, `cw_toplevel`, `cw_popup`, `cw_layer`, `cw_decoration` | C13 |
| `canvas-policy.cwp` | `cw_policy` | C13 |
| `canvas-data.cwp` | `cw_data` | C15 |
| `canvas-text.cwp` | `cw_text` | C16 |
| `canvas-a11y.cwp` | `cw_a11y` | C16 |
| `canvas-capture.cwp` | `cw_capture` (privileged) | C17 |
| `canvas-inject.cwp` | `cw_inject` (privileged) | C17 |
| `canvas-session.cwp` | `cw_session` | C18 |
| `canvas-debug.cwp` | `cw_debug` (privileged) | C20 |
| `canvas-remote.cwp` | `cw_remote` | C26 |

## Syntax

```
protocol <name> <version> {
    interface <name> <version> {
        request <name>(<args>) -> (<ret>)
        event <name>(<args>)
        enum <name> { <values> }
        struct <name> { <fields> }
    }
}
```

## Types

- `int` / `uint` — 32-bit signed/unsigned
- `long` / `ulong` — 64-bit signed/unsigned
- `fixed` — 16.16 fixed-point
- `string` — null-terminated UTF-8
- `handle` — generation-tagged object reference
- `fd` — file descriptor (not used in Canvas)
- `array<T>` — variable-length array
- `bool` — boolean (0/1)

## Code Generation

Run `cwpgen` (built in C4) to generate:
- `inc/gen/cwp_*.inc` — constants, structs, opcode enums
- `src/proto/gen/gen_*.asm` — dispatch tables, encode/decode
- `src/client/gen/client_*.asm` — client stubs
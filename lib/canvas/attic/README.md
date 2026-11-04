# Attic

Source files that are not part of the Canvas build, kept at their original
paths (`attic/src/...`, `attic/tests/...`, `attic/tools/...`) so their history
and ideas stay at hand. Nothing here is assembled, linked or scanned by
`make layout-check`; nothing in the build references their symbols.

Most are earlier drafts of a module that was later written again elsewhere.
Code worth keeping from one moves into the live module; a file is not
brought back as it is.

## Superseded by a live module

| Attic file | Why | Live module |
|---|---|---|
| `src/backend/fb_linear/fb_linear.asm` | does not assemble; every global also in the live one | `src/backend/fb_linear/fb_linear_full.asm` |
| `src/backend/headless/headless.asm` | does not assemble; every global also in the live one | `src/backend/headless/headless_full.asm` |
| `src/backend/native/native_hotplug.asm` | does not assemble | `src/backend/native/native_full.asm` |
| `src/backend/native/native_modeset.asm` | does not assemble | `src/backend/native/native_full.asm` |
| `src/backend/native/native_vblank.asm` | a copy of the vblank path written for the retired compositor; calls `frame_clock_schedule_vblank`, which no longer exists | `src/server/frame_clock/frame_clock.asm` (`frame_clock_vblank`) |
| `src/codec/png.asm` | does not assemble | `src/img/png.asm` |
| `src/compositor/*.asm` (compositor, damage, frame_clock, output, surface) | do not assemble; the first compositor | `src/render/compositor.asm`, `src/server/damage`, `src/server/frame_clock`, `src/output/output.asm`, `src/server/surface` |
| `src/core/arena_full.asm` | assembles, but 7 of its 10 globals duplicate the live arena | `src/core/arena.asm` |
| `src/gpu/gpu_renderer.asm` | does not assemble | `src/render/gpu_render.asm` |
| `src/input/clipboard.asm`, `src/input/dnd.asm` | do not assemble | `src/data/clipboard.asm`, `src/data/dnd.asm` |
| `src/input/ime_bridge.asm`, `src/input/text_input.asm` | do not assemble | `src/text/ime_bridge.asm`, `src/text/text_input.asm` |
| `src/input/manager.asm` | does not assemble | `src/input/input.asm` |
| `src/input/seat.asm`, `src/input/keyboard.asm`, `src/input/pointer.asm`, `src/input/focus.asm`, `src/input/hittest.asm` | assemble, but never ran: nothing created a seat. Functions saved registers and returned without restoring them, the first device added became the seat itself, and the hit test read a surface size nothing sets | `src/input/input.asm` |
| `src/input/keymap.asm` | two keys of a US layout | `src/input/keymap_us.asm` |
| `src/input/source_ut.asm` | a source object for the kernel's input that did nothing; input.asm registers for it directly | `src/input/input.asm` |
| `src/shell/shell.asm`, `workspace.asm`, `states.asm`, `move_resize.asm`, `rules.asm`, `theme.asm` | assemble, but nothing called them: no request reached a shell. Stack frames popped fewer registers than they pushed, calls passed the wrong arguments, a seat read from a struct that never had one | `src/shell/window.asm`, `src/shell/stacking.asm`, Alt+drag in `src/input/input.asm` |
| `src/shell/popup.asm`, `src/shell/layer.asm` | the same; their `popup_create` and `layer_create` clashed with the working roles | `src/shell/window.asm` |
| `src/policy/policy_floating.asm`, `policy_tiling.asm`, `policy_kiosk.asm`, `policy_external.asm`, `layout_engine.asm` | assemble, unreachable; floating's struct overlaid `Policy` field for field | placement and stacking in `src/shell/window.asm`, `stacking.asm` |
| `src/text/shortcuts.asm` | unreachable | Alt+F4 and Alt+drag in `src/input/input.asm` |
| `src/protocol/*.asm` (connection, dispatch, wire) | do not assemble; the first wire layer | `src/proto/*` |
| `src/shell/layout.asm`, `src/shell/policy.asm` | do not assemble | `src/policy/layout_engine.asm`, `src/policy/*` |
| `tools/cwpgen/main.asm` | does not assemble | `src/tools/cwpgen.asm` |

## An earlier conformance suite

| Attic file | Why | Live suite |
|---|---|---|
| `tests/cts/cts_runner.asm`, `tests/cts/test_*.asm` (compositor, gpu, input, performance, protocol, regression, render, security, shell, stress) | do not assemble | `tests/cts/cts_*.asm`, `tests/cts_runner.asm` |
| `tests/cts/cts_common.asm` | assembles; helpers only that earlier suite used | |

# Decision 0013: Input Devices and Their Records

**Status**: Accepted (2026-11-09), built
**Date**: 2026-11-09
**Phase**: P2 (TCH-01, TCH-02, TCH-10, SES-08, WIN-21)

## Context
Canvas takes all input as 24-byte raw records (`KERNEL_NEEDS.md` step 3).
Types 1 to 5 (keys, motion, position, buttons, scroll) came first. Touch
screens, pens, touchpads, switches and hot-plugged devices need more, and
the same record (a contact, say) means different things on different
devices: a finger on a touch screen points at the screen, a finger on a
touchpad does not.

## Options
| Option | Problem |
|---|---|
| A. A record type per device kind (touch-screen contact, touchpad contact) | Drivers must know what Canvas does with each; types multiply |
| B. One record per kind of event; the device's capabilities say what it means | Canvas must ask about the device |
| C. Drivers make gestures and pointer motion themselves | Gesture policy in every driver; no server-wide gestures |

## Decision
**Option B.**

- **Records.** Types 6 to 10 (agreed with `lib/input`, decision I3): touch
  contact, pen position, pen axes, switch, device change. Type 11, the pen
  tablet's pad (buttons, rings, strips), is proposed by Canvas and not yet
  agreed; Canvas routes it already.
- **What a device is** comes from `ut_input_device_info`'s `caps`: touch (4)
  alone is a touch screen, mapped onto the first output in device units;
  pointer and touch (2 and 4) together is a touchpad, whose contacts become
  gestures and are never mapped onto the screen; its driver still sends the
  pointer's motion and taps as types 2 and 4.
- **Who gets what.**
  - A finger belongs to the surface it went down on until it lifts.
  - The pen goes to the surface under it, or the one it touched while its
    tip is down.
  - The pad goes to the surface with the keyboard.
  - Gestures go to the surface under the pointer when the fingers went down.
  - Switches and device changes go to the clients watching the seat
    (`cw_seat`, `CAP_SEAT`).
- **The server keeps some for itself.** Four or more touchpad fingers moving
  together switch workspaces and are never sent to a client. The lid switch
  is the server's too (decision 0014).
- **Pen pressure** can be shaped by one curve for the seat
  (`server_set_pen_curve`): a cubic through two heights, using `lib/umath`'s
  Bézier evaluation.

## Consequences
- `input/input` dispatches every type; `input/gestures` holds the touchpad
  state; `input/seat_watch` the watchers.
- Device info is asked for on each contact record; a cache can come when it
  shows in a profile.
- A device removed has its fingers cancelled.
- Not yet: per-device settings (which output a touch screen maps to,
  per-tool pressure curves, pad modes), multi-finger taps, pinch rotation.

## Related
- `KERNEL_NEEDS.md` step 3; `lib/input/ROADMAP.md` §5.2 (decision I3)
- ROADMAP TCH-01, TCH-02, TCH-10, SES-08, WIN-21
- `proto/canvas-input.cwp`

## Revisit Criteria
If `lib/input` changes type 11 when it agrees it, or if a device kind turns
up whose capabilities do not say what its records mean.

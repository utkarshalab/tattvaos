# Decision 0014: What Closing the Lid Does

**Status**: Accepted (2026-11-09), built
**Date**: 2026-11-09
**Phase**: P2 (SES-08)

## Context
A laptop's lid switch (record type 9, switch 0) is the most common power
event a desktop sees. What it should do depends on whether the laptop is
docked: with another screen on, people keep working with the lid shut; with
none, they expect the session to be safe and the machine to sleep.

## Options
| Option | Problem |
|---|---|
| A. The lid always locks and suspends | A docked laptop sleeps under its user |
| B. The lid does nothing; a policy client decides | Nothing happens until one exists; a crashed client leaves the session open |
| C. The server decides by what screens are on | It must know which screen is the built-in one |

## Decision
**Option C.**

- **The built-in panel** is the output whose framebuffer the kernel marks
  with bit 0 of `ut_fb_info`'s flags (`KERNEL_NEEDS.md` step 5). Canvas zeroes
  the flags first, so an older kernel's outputs are simply not built-in.
- **Lid closed:**
  - The built-in panel is turned off.
  - If another screen shows the layout, the panel becomes a mirror of it, so
    it is no part of the layout, and its windows move there. The session
    stays unlocked.
  - If not, the login screen comes up, and then Canvas asks the kernel to
    suspend (`ut_power_suspend`). Without that export, or with
    `server_set_lid_sleep(server, 0)`, it only locks.
- **Lid closed, then the other screen unplugged:** as if the lid had just
  closed with no other screen, so it locks and sleeps.
- **A screen plugged in with the lid closed** takes the panel's place.
- **Lid opened:** what closing it did is undone (the panel on, back in the
  layout). It does not unlock; the password is still needed.
- **Watchers** (`cw_seat`) hear of the lid like any switch.

## Consequences
- `output/clamshell` holds the policy; `input/input` and `server_core` call
  it on the lid and on outputs added and removed.
- Locking before suspending means the login screen is what shows on waking.
- Not yet: a client that inhibits suspend (video playing with the lid shut
  and a screen on is already handled by the dock case), suspend on idle,
  battery-level policy.

## Related
- `KERNEL_NEEDS.md` steps 3 and 5; `docs/utkarsha-contract.md` §3.12
- ROADMAP SES-08; decision 0013

## Revisit Criteria
If users want the lid to do something else (a setting per lid action), or
the kernel takes over suspend policy itself.

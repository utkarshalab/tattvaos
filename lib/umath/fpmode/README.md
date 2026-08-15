# fpmode — umath FPU/SSE Rounding Mode Control

**Module:** `fpmode/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Control of the FPU/SSE rounding-mode state itself: `MXCSR` manipulation to
switch between round-to-nearest, toward-zero, toward-+∞, toward-−∞, plus
the flush-to-zero (FTZ) and denormals-are-zero (DAZ) flags that matter for
performance-sensitive code that doesn't need subnormal precision.
`scalar/round_f32.asm`'s `roundss`/`roundps` instructions take their
rounding mode as an *immediate operand per call* and don't touch this
global state at all — this module and `scalar/round_f32.asm` address
genuinely different problems: "round this value now, this way" vs. "what
does the CPU do by default when it rounds."

This module was originally scaffolded as `round/`, which collided on
first read with `scalar/round_f32.asm`/`round_f64.asm` (per-value
rounding, already implemented). Renamed to remove the ambiguity.

## Planned scope

- `fpmode_set_rounding`/`fpmode_get_rounding` — MXCSR rounding-mode field
- `fpmode_set_ftz_daz`/`fpmode_get_ftz_daz` — subnormal handling flags
- A scoped save/restore helper (set a mode for one computation, restore the
  caller's mode after) — global FPU state is exactly the kind of thing
  that's easy to leak across a function boundary by accident

## Dependencies (anticipated)

```
fpmode/ depends on:
  → nothing (Tier 0, MXCSR register access)

fpmode/ is depended on by:
  → any module that needs a non-default rounding mode or FTZ/DAZ for a
    bounded region of code
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# diag — umath Diagnostic Logging

**Module:** `diag/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Math-domain diagnostic/instrumentation logging: recording overflow,
underflow, NaN-producing operations, denormal encounters, and similar
numerically-interesting events during a math kernel's execution — the kind
of thing you'd want breadcrumbed when a GEMM run produces unexpected NaNs
three layers deep. Distinct from `lib/ulog/` at the repo's top level
(general structured logging for the whole OS); this would be a
lightweight, math-specific facility layered on top of it, if it's needed
at all rather than just using `ulog/` directly.

This module was originally scaffolded as `log/`, which collided on first
read with `math_fn/log_f32.asm`/`log_f64.asm` (the natural logarithm,
already implemented). Renamed to remove the ambiguity rather than carry
two same-named things side by side.

## Planned scope

- Hook points other umath modules can call into on numerically notable
  events (NaN produced, overflow saturated, denormal flushed)
- Cheap enough to leave enabled in normal builds, or gated like `assert/`

## Dependencies (anticipated)

```
diag/ depends on:
  → lib/ulog/  (if this ends up being a thin math-specific wrapper rather
                 than its own facility)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

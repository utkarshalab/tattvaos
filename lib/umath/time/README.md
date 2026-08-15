# time — umath Cycle-Accurate Kernel Timing

**Module:** `time/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

High-resolution, cycle-accurate timing specifically for measuring math
kernels — the wall-clock/calendar side (RTC, ACPI timers, date formatting)
already lives in the top-level `lib/time/` module (its own directory with
its own `Makefile`, distinct from this one nested inside `umath/`). This
module is `perf/`'s `RDTSC`-based cycle counting turned into elapsed-time
measurements specifically for benchmarking `gemm/`/`math_fn/` kernels,
paired closely with `profile/`. Given `lib/time/` already exists and
handles the general case, this folder may end up being a thin wrapper
around it rather than its own implementation — worth checking when this
folder's turn in the sweep actually comes, rather than assuming it needs a
full independent implementation.

## Planned scope (tentative — possibly a thin wrapper, see above)

- Elapsed-time measurement built on `perf/`'s cycle counters and TSC
  frequency calibration
- Timeout/deadline helpers for anything in `gemm/` that yields
  mid-computation (works with `thread/`'s fiber integration)

## Dependencies (anticipated)

```
time/ depends on:
  → perf/       (raw cycle counting)
  → lib/time/   (TSC calibration, if not duplicating that work)

time/ is depended on by:
  → profile/  (elapsed-time reporting alongside cycle counts)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

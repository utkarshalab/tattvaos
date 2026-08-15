# profile — umath Kernel Profiling Instrumentation

**Module:** `profile/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Turns `perf/`'s raw cycle/PMC counter reads into usable instrumentation:
named timing spans, per-kernel-variant call counters, and the comparison
harness that answers "is the AVX2 or AVX-512 `memcpy` actually faster on
this specific CPU" at runtime rather than by assumption. This is the
consumer `perf/README.md` already points to as the reason that module's
raw counters exist.

## Planned scope

- `profile_span_begin/end` — named timing span, accumulates min/max/mean/
  count
- `profile_report` — dump accumulated spans (through `diag/` or directly
  to serial)
- Variant-comparison harness: run N candidate implementations of the same
  operation, report which was fastest — the mechanism `gemm_bench.asm` and
  `simd_bench.asm` (per `PROJECTSTRUCTURE.md`) are expected to use

## Dependencies (anticipated)

```
profile/ depends on:
  → perf/  (raw cycle/PMC counters)

profile/ is depended on by:
  → gemm/, simd/  (benchmark harnesses comparing kernel variants)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

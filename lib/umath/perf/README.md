# perf — umath Performance Counter Access

**Module:** `perf/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Low-level performance counter access — `RDTSC`/`RDTSCP` cycle counting and
`RDPMC` hardware performance-monitoring-counter reads — for measuring math
kernels precisely. This is the raw counter-reading primitive; `profile/`
(a separate planned module) is where that gets turned into "which
`memcpy` variant is actually fastest on this CPU" instrumentation, similar
to how `atomic/` is the raw CAS and `lock/` is the policy built on it.

## Planned scope

- `perf_rdtsc`, `perf_rdtscp` — cycle counters, with the serializing/
  non-serializing tradeoff documented at the call site
- `perf_rdpmc` — hardware PMC read, given a counter index
- Calibration helper: cycles-per-nanosecond, needed to turn a cycle delta
  into wall-clock time without relying on a fixed TSC frequency assumption

## Dependencies (anticipated)

```
perf/ depends on:
  → cpuid/  (whether RDTSCP/invariant TSC/PMC are available)

perf/ is depended on by:
  → profile/  (turns raw counter reads into kernel-comparison instrumentation)
  → gemm/, math_fn/  (benchmark harnesses)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

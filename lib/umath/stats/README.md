# stats — umath Descriptive Statistics

**Module:** `stats/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Descriptive statistics over numeric arrays: mean, variance, standard
deviation, median, percentiles. Note this is a different `stats` from
`memory/stats.asm`, which tracks *allocator* statistics
(current/peak/average allocation, per-bin counts) — that one instruments
`memory/`'s own allocators, this one computes statistics *of the numeric
data* a caller hands it. Two modules answering to the same short name for
genuinely different subjects; not renamed the way `log/`, `prefetch/`,
`round/`, and `traits/` were, since `memory/stats.asm` lives inside
`memory/` rather than being its own top-level folder and the "statistics
of X" reading is unambiguous in context — but worth noting so neither gets
mistaken for the other.

## Planned scope

- `stats_mean_f32/f64`, `stats_variance_f32/f64`, `stats_stddev_f32/f64` —
  built on `stability/`'s Welford's-algorithm implementation, not the
  naive two-pass formula
- `stats_median_f32/f64` (exact, via `sort/`) and `stats_percentile`
  (approximate, via `histogram/`, for large arrays where an exact sort is
  too expensive)
- `stats_summary` — mean/var/min/max/count in one pass, the common case
  when profiling a tensor's distribution

## Dependencies (anticipated)

```
stats/ depends on:
  → stability/   (Welford's algorithm for variance)
  → reduce/      (mean is a sum reduction)
  → sort/, histogram/  (median, percentiles)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

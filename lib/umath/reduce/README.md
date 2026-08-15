# reduce — umath Array Reductions

**Module:** `reduce/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Reduction operations over arrays: sum, product, min/max-reduce, argmin/
argmax. The building block `norm/`'s sum-of-squares and `stats/`'s
mean/variance both need underneath — rather than each of those modules
implementing its own unrolled accumulation loop, they call into a shared,
already-optimized reduction here.

## Planned scope

- `reduce_sum_f32/f64`, `reduce_product_f32/f64` — pairwise or
  Kahan-compensated summation matters for large arrays (see
  `stability/README.md` for why naive summation isn't good enough at
  scale)
- `reduce_max/min_f32/f64/i32/i64`, plus `argmax`/`argmin` returning the
  index
- Blocked/tree reduction for arrays too large for a single accumulator to
  stay numerically stable

## Dependencies (anticipated)

```
reduce/ depends on:
  → scalar/     (per-element min/max/compare)
  → stability/  (compensated summation for the sum path)

reduce/ is depended on by:
  → norm/, stats/, histogram/  (every array-summary operation)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# stability — umath Numerically Stable Algorithm Variants

**Module:** `stability/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

The numerically-careful versions of otherwise-simple reductions: naive
summation of a large float array accumulates rounding error linearly in
the array length, naive variance computation (`E[x²] - E[x]²`) can produce
a negative "variance" from floating-point cancellation, and a naive softmax
overflows `exp()` for large inputs. `stability/` is where the
compensated/rearranged algorithms that avoid these failure modes live —
consumed by `reduce/` and `stats/` rather than each of those reimplementing
the careful version inline.

## Planned scope

- Kahan (and Neumaier-variant) compensated summation
- Welford's online algorithm for variance/stddev (single pass, numerically
  stable, what `stats/` should use instead of the naive two-moment
  formula)
- Pairwise/tree summation as a cheaper partial alternative to full Kahan
  compensation
- Log-sum-exp (the standard numerically-stable softmax building block:
  subtract the max before exponentiating, so `math_fn/exp_f32`'s clamping
  never saturates on the way to a normalized probability)

## Dependencies (anticipated)

```
stability/ depends on:
  → math_fn/  (log-sum-exp needs exp/log)
  → scalar/   (max, for the log-sum-exp shift)

stability/ is depended on by:
  → reduce/, stats/, norm/  (every reduction that cares about accumulated
                              error at scale)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

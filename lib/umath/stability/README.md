# stability — umath Numerically Stable Algorithm Variants

**Module:** `stability/`
**Status:** Implemented — compensated and pairwise sums, Welford mean/variance, log-sum-exp.
**Tier:** 1 (depends on `math_fn/` for exp/log)
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

---

## Files

```
stability/
├── kahan_f64.asm / kahan_f32.asm         ← Neumaier-compensated sum: array
│                                            version (4 lanes, branch-free
│                                            packed step) + streaming state
├── pairwise_f64.asm / pairwise_f32.asm   ← pairwise (cascade) sum: 256-element
│                                            SIMD leaves merged like a binary
│                                            counter, no recursion
├── welford_f64.asm / welford_f32.asm     ← mean/variance state: one-sample
│                                            Welford push, corrected two-pass
│                                            batch update, Chan merge
└── logsumexp_f64.asm / logsumexp_f32.asm ← max + log(sum(exp(x - max)))
```

## API

```
umath_kahan_sum_f64(src, n)        -> xmm0      compensated sum
umath_kahan_sum_f32(src, n)        -> xmm0 f32  (accumulates in double)
umath_kahan_init_f64(state)                     state = { f64 sum, f64 comp }
umath_kahan_add_f64(state, x) / umath_kahan_add_f32(state, x)
umath_kahan_result_f64(state) / umath_kahan_result_f32(state)

umath_pairwise_sum_f64(src, n)     -> xmm0
umath_pairwise_sum_f32(src, n)     -> xmm0      (float throughout)

umath_welford_init(state)                       state = { u64 count, f64 mean, f64 m2 }
umath_welford_push_f64(state, x) / umath_welford_push_f32(state, x)
umath_welford_update_f64(state, src, n) / umath_welford_update_f32(state, src, n)
umath_welford_merge(a, b)                       a = a combined with b
umath_welford_count(state) -> rax
umath_welford_mean(state) -> xmm0               NaN if empty
umath_welford_variance(state, ddof) -> xmm0     m2 / (count - ddof), NaN if count <= ddof

umath_logsumexp_f64(src, n)        -> xmm0
umath_logsumexp_f32(src, n)        -> xmm0 f32  (evaluated in double)
```

Empty or NULL arrays: sums return 0, log-sum-exp returns -Inf.

---

## Design decisions, and why

**Neumaier, not plain Kahan.** Plain Kahan always computes the correction
as `(s - t) + x`, which is wrong whenever the addend is larger than the
running sum (`[1, 1e100, 1, -1e100]` sums to 0 instead of 2). Neumaier
picks `(x - t) + s` in that case. The packed version does both and blends
by an `|x| <= |s|` mask, so the hot loop has no branches. Once the sum is
not finite the correction is meaningless (`Inf - Inf = NaN`), so the
result is the plain sum then: an Inf addend gives Inf, not NaN.

**f32 compensated sums accumulate in double.** Widening is exact and a
compensated double carries far more than float's 24 bits, so the float
result is the correctly rounded sum in practice, for one `cvtps2pd` per
two elements.

**Pairwise as the cheap option.** Each lane of a 256-element leaf adds at
most 32 (f64) or 16 (f32) terms and leaves merge pairwise, so the error
grows with `log2(n)` rather than `n` — e.g. a million copies of 0.1 stay
accurate — at essentially the cost of a plain vectorized loop. It makes no
promise under cancellation; use the Kahan sum for that.

**Welford state merges.** Besides the one-sample update, a whole array is
added with the corrected two-pass method (compensated mean, then
`m2 = sum(d²) - sum(d)²/n` over deviations `d`) and merged into the state
with Chan's formula. Merging is exact algebra, so per-chunk or per-thread
states combine into the same answer as one pass. Data offset by 1e9 with
unit spread, where `E[x²] - E[x]²` loses everything, keeps ~1e-9 relative
variance accuracy.

**log-sum-exp shifts by the max.** Every `exp` argument is `<= 0` and the
largest term is exactly 1, so nothing overflows and the log never sees 0.
Both passes are packed: the max with `maxpd`/`maxps` and a separate NaN
flag, the exponentials through `exp_f64`'s two-lane core into a packed
Neumaier accumulator (2.3x faster than one scalar exp call per element).
Special values: any NaN → NaN, a `+Inf` element → `+Inf`, all `-Inf` →
`-Inf`. A stable softmax is `exp(x_i - logsumexp(x))`.

---

## Verification

`tests/test_stability.py` (run by `tests/run_tests.sh`) compares against
exact references: `math.fsum` (correctly rounded sum) and `Fraction`
arithmetic for mean/variance. Measured: Kahan sums within 2 ULP (f64) /
1 ULP (f32) of the correctly rounded sum including heavy cancellation;
pairwise sums within `(lane terms + log2 n) · eps · sum|x|`; Welford
mean within a few eps of the data's magnitude and variance within 1e-9
relative (chunked + merged runs match); log-sum-exp within 4 ULP (f64) /
1 ULP (f32), including inputs of ±1000 where the naive form overflows.

---

## Dependencies

```
stability/ depends on:
  → math_fn/  (exp_f64 and log_f64, for log-sum-exp)

stability/ is depended on by:
  → reduce/, stats/, norm/  (every reduction that cares about accumulated
                              error at scale)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

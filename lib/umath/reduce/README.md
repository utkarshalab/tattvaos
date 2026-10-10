# reduce — umath Array Reductions

**Module:** `reduce/`
**Status:** Implemented — sum/mean, dot/sum of squares, overflow-safe product, exact integer sums.
**Tier:** 1 (depends on `stability/`)
**Part of:** umath — unified math library

---

## Purpose

Reduction operations over arrays: the building blocks `norm/`'s
sum-of-squares and `stats/`'s mean/variance need underneath, so those
modules call a shared, already-careful reduction here instead of each
implementing its own accumulation loop.

Min/max reductions and argmin/argmax already live in `scalar/`
(`umath_min_f64_reduce`, `umath_max_f32_reduce_index`, ...; NaN-propagating)
and are not duplicated here.

---

## Files

```
reduce/
├── sum_f64.asm / sum_f32.asm     ← reduce_sum (pairwise) and reduce_mean
│                                    (compensated sum / n)
├── dot_f64.asm / dot_f32.asm     ← reduce_dot and reduce_sumsq, pairwise
│                                    cascade over SIMD leaf blocks
├── prod_f64.asm / prod_f32.asm   ← reduce_prod with mantissa/exponent
│                                    tracking (no intermediate overflow)
└── sum_int.asm                   ← exact i32/u32 sums in 64 bits, i64/u64
                                     sums in 128 bits
```

## API

```
umath_reduce_sum_f64(src, n)   / _f32  -> xmm0   pairwise sum, 0 if empty
umath_reduce_mean_f64(src, n)  / _f32  -> xmm0   compensated mean, NaN if empty
umath_reduce_dot_f64(a, b, n)  / _f32  -> xmm0   sum of a[i]*b[i]
umath_reduce_sumsq_f64(src, n) / _f32  -> xmm0   sum of src[i]^2
umath_reduce_prod_f64(src, n)  / _f32  -> xmm0   product, 1 if empty
umath_reduce_sum_i32(src, n) -> rax (int64)      exact for n < 2^32
umath_reduce_sum_u32(src, n) -> rax (uint64)     exact for n < 2^32
umath_reduce_sum_i64(src, n) -> rdx:rax (int128) exact
umath_reduce_sum_u64(src, n) -> rdx:rax (uint128) exact
```

---

## Design decisions, and why

**Sums pick their algorithm from `stability/`.** `reduce_sum` is the
pairwise sum (error grows with `log2(n)`, about the cost of a plain loop);
for a result within 2 ULP regardless of cancellation call
`umath_kahan_sum_*` directly. `reduce_mean` uses the compensated sum,
since a mean is usually reported as is; the f32 mean keeps the sum in
double until after the division, so it rounds to float once.

**Dot products use the same cascade.** 256-pair leaves in eight (f64) or
sixteen (f32) SIMD lanes, leaves merged like a binary counter. Each
product is rounded before it is added: there is no FMA, which the
baseline target doesn't guarantee.

**The product tracks its exponent separately.** A running product
overflows or underflows long before the result does (`[1e200, 1e200,
1e-200, 1e-200]` is Inf, not 1). Each factor is split into mantissa and
exponent, the mantissa product is kept in `[1, 2)` with exact halvings,
the exponents are summed as an integer, and the result is scaled once at
the end — overflowing to Inf or underflowing through subnormals exactly
when the true product does. A subnormal result can be one subnormal ULP
off (the mantissa product, already rounded, is rounded again). Any NaN →
NaN, zero times Inf → NaN, signs are tracked through zeros and infinities.

**Integer sums widen instead of wrapping.** 32-bit elements accumulate in
64-bit SIMD lanes; 64-bit elements carry into a 128-bit result returned
in `rdx:rax`, the System V layout of a 128-bit integer.

---

## Verification

`tests/test_reduce.py` (run by `tests/run_tests.sh`) uses exact
`Fraction` references: means within 2 ULP (f64) / 1 ULP (f32) including
large offsets, dot/sumsq within `(lane terms + log2 n + 2) · eps ·
sum|a·b|`, products within `(n + 2) · eps` relative plus the
no-intermediate-overflow, subnormal and special-value cases, and integer
sums exact at the extremes of each type.

---

## Dependencies

```
reduce/ depends on:
  → stability/  (pairwise and compensated sums)

reduce/ is depended on by:
  → norm/, stats/, histogram/  (every array-summary operation)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

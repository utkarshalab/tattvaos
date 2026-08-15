# norm — umath Vector/Matrix Norms

**Module:** `norm/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Vector and matrix norms — L1, L2 (Euclidean), L-infinity, Frobenius — the
kind of reduction that every normalization layer in an AI workload
(layer-norm, RMS-norm, weight normalization) needs repeatedly. This is one
of the modules that directly consumes `math_fn/sqrt_f32`/`sqrt_f64` (L2
norm is a sum-of-squares reduction followed by a square root) and
`reduce/`'s planned sum/reduction primitives.

## Planned scope

- `norm_l1_f32/f64`, `norm_l2_f32/f64`, `norm_linf_f32/f64` over an array
- `norm_frobenius_f32/f64` for a matrix (flattened, same computation as L2
  over the flattened array, kept as a distinct named entry point since
  callers reason about it as a matrix operation)
- Normalized-in-place variants (`normalize_l2_f32_inplace`: divide every
  element by the computed norm) — RMS-norm and friends build directly on
  this

## Dependencies (anticipated)

```
norm/ depends on:
  → math_fn/  (sqrt for L2/Frobenius)
  → reduce/   (sum-of-squares reduction)
  → scalar/   (abs, max for L1/Linf)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

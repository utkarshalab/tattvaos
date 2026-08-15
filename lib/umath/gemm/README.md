# gemm — umath Matrix Multiply Kernels

**Module:** `gemm/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

General matrix multiply — the operation the `README.md` at the top of
`lib/umath/` calls out by name as a reason this library exists
("optimized for AI workloads"). This is where `simd/`'s vectorized
dot-product/FMA primitives, `cache/`'s tile-size selection, and
`memory/`'s scratch-buffer allocators come together into an actual blocked
GEMM implementation, plus architecture-specific variants and a benchmark
harness to compare against.

## Planned scope

Per `PROJECTSTRUCTURE.md`'s existing plan for this module:

- `gemm.asm` — general/reference GEMM (correctness baseline)
- `gemm_x86.asm` — AVX2/AVX-512/AMX-tiled x86 kernel
- `gemm_aarch64.asm` — NEON/SVE kernel (for whenever TattvaOS targets
  aarch64)
- `gemm_bench.asm` — benchmark harness, the natural point of comparison
  being cuBLAS/MKL-class throughput per `PROJECTSTRUCTURE.md`'s stated
  goal

This is one of the largest and most performance-critical modules planned
for umath — expect it to need `simd/`, `cache/`, and `dtype/` finished
first, in that rough order, before a blocked kernel here is worth writing.

## Dependencies (anticipated)

```
gemm/ depends on:
  → simd/    (vectorized FMA/dot-product primitives)
  → cache/   (tile-size selection for blocking)
  → memory/  (scratch-buffer allocation)
  → dtype/   (mixed-precision accumulation rules)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

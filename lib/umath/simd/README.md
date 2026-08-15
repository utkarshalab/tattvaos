# simd — umath SIMD Dispatch & Vectorized Primitives

**Module:** `simd/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Architecture-specific vectorized primitives — dot product, FMA-based
multiply-accumulate, elementwise transcendental application — one level
above what `scalar/`'s already-packed `_array` functions provide.
`scalar/`'s array variants are unrolled SSE `ps`/`pd` operations baked
directly into each file; `simd/` is where AVX2/AVX-512/AMX (x86) and
NEON/SVE (aarch64, per `PROJECTSTRUCTURE.md`) variants of the operations
that benefit most from wider vectors live, selected at runtime via
`cpuid/`.

## Planned scope

Per `PROJECTSTRUCTURE.md`'s existing plan for this module:

- `avx2.asm` / `avx512.asm` — x86 wide-vector kernels
- `amx.asm` — Intel AMX tile-matrix instructions
- `neon.asm` / `sve.asm` — aarch64 equivalents
- Runtime dispatch tying into `cpuid/`'s feature detection, so callers get
  the widest vector width the actual CPU supports without hand-picking a
  variant (contrast `memory/`'s current plain/SSE/AVX2/AVX512 functions,
  which are still separate symbols the caller picks manually — `simd/` is
  where that dispatch becomes automatic)

## Dependencies (anticipated)

```
simd/ depends on:
  → cpuid/   (runtime feature dispatch)
  → dtype/   (width/dtype-aware vectorization)

simd/ is depended on by:
  → gemm/  (the FMA/dot-product primitives a blocked matrix multiply needs)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

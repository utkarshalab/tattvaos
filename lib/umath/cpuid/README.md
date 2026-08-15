# cpuid — umath CPU Feature Detection

**Module:** `cpuid/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Runtime CPU feature detection via the `CPUID` instruction: SSE/SSE2/SSE4.1/
SSE4.2, AVX/AVX2/AVX-512 (and which sub-features), FMA3, POPCNT, BMI1/2,
RDRAND — feeding the runtime dispatch every "plain/SSE/AVX2/AVX512"
variant trio in `memory/` (and eventually `simd/`, `gemm/`) currently
leaves to the caller to pick manually. `dtype/dtype_support.asm` already
calls into this module (per its own README) to answer "is this dtype's
representation supported on the current CPU" — `cpuid/` is the thing that
actually executes `CPUID` and caches the result; `dtype_support` is one of
its consumers.

## Planned scope

- `cpuid_detect` — run once at boot, cache the feature bitmask
- `cpuid_has_avx2`, `cpuid_has_avx512f`, `cpuid_has_fma`, `cpuid_has_popcnt`,
  etc. — cheap queries against the cached bitmask
- A dispatch-table helper: given a set of variant function pointers keyed
  by required feature, return the best one available (used to pick
  `memcpy` vs `memcpy_avx2` vs `memcpy_avx512` once, not per call)

## Dependencies (anticipated)

```
cpuid/ depends on:
  → nothing (Tier 0, raw CPUID instruction wrapper)

cpuid/ is depended on by:
  → dtype/  (dtype_support.asm)
  → cache/  (cache size/line-size leaves)
  → every module with plain/SSE/AVX2/AVX512 variants, for dispatch
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

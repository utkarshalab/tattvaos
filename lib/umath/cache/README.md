# cache — umath Cache-Aware Layout Helpers

**Module:** `cache/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Cache-topology-aware helpers for data layout: cache-line size queries,
false-sharing padding, and cache-oblivious/cache-blocking layout decisions
for the tiled loops `gemm/` needs. Distinct from `memory/prefetch.asm`
(which issues prefetch *instructions*) and `memory/align.asm`'s
`mem_align_cacheline` (which aligns a single pointer) — `cache/` is where
decisions about *how to lay out and block* data for cache behavior live,
one level of policy above those primitives.

## Planned scope

- Cache-line size constant(s) and runtime query (feeds from `cpuid/` once
  that exists)
- Padding helpers to avoid false sharing between per-core/per-fiber
  counters
- Cache-blocking tile-size calculators for `gemm/`'s blocked matrix
  multiply (given L1/L2 size, working-set size, dtype width, pick a tile
  size that fits)

## Dependencies (anticipated)

```
cache/ depends on:
  → cpuid/   (cache size/line-size detection)
  → memory/  (alignment primitives)

cache/ is depended on by:
  → gemm/  (tile-size selection for blocked matrix multiply)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

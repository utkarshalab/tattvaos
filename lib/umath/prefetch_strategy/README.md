# prefetch_strategy — umath Prefetch Scheduling

**Module:** `prefetch_strategy/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Where to issue a prefetch and how far ahead — access-pattern-aware
prefetch *scheduling* for `gemm/`'s tiled loops and other strided access
patterns, built on `memory/prefetch.asm`'s instruction-level primitives the
same way `cache/`'s tile-size selection is policy built on
`memory/align.asm`'s primitives.

This module was originally scaffolded as `prefetch/`, which collided on
first read with `memory/prefetch.asm` (the raw prefetch-instruction
wrappers, already implemented). Renamed to remove the ambiguity: this
folder is the strategy/scheduling layer, `memory/prefetch.asm` is the
instruction-level primitive it's built on.

## Planned scope

- Stride/distance calculators: given an access pattern and cache-line
  size, how many iterations ahead to prefetch
- GEMM-tile-specific prefetch scheduling, coordinated with `cache/`'s
  tile-size decisions

## Dependencies (anticipated)

```
prefetch_strategy/ depends on:
  → memory/  (the actual prefetch instruction wrappers)
  → cache/   (cache-line size, tile geometry)

prefetch_strategy/ is depended on by:
  → gemm/  (tiled-loop prefetch scheduling)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

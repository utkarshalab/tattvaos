# capability — umath Operation & Platform Capability Traits

**Module:** `capability/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Generic capability/property queries that aren't about a specific dtype:
"is this operation associative" (matters for whether a reduction can
safely be reordered/parallelized), "is this function branchless" — the
kind of trait query that's about an *operation* or the *platform*, where
`dtype/dtype_traits.asm` is specifically about a *dtype* (`has_nan`,
`has_inf`, `has_subnormal`, etc.). Raw platform feature bits (AVX2
present, FMA present) belong to `cpuid/` directly — if what ends up here
turns out to be redundant with `cpuid/`, that's a sign this module should
shrink to just the operation-property side rather than duplicate it.

This module was originally scaffolded as `traits/`, which collided on
first read with `dtype/dtype_traits.asm` (per-dtype numeric traits,
already implemented). Renamed to remove the ambiguity.

## Planned scope

- Operation-property traits: associativity/commutativity flags for
  `reduce/`'s reduction operations (affects whether parallel/tree
  reduction is valid)
- Anything capability-shaped that isn't a raw `cpuid/` feature bit and
  isn't a per-dtype numeric trait — narrow scope is deliberate here,
  given how easily this could re-collide in purpose (not just name) with
  either of those two modules

## Dependencies (anticipated)

```
capability/ depends on:
  → cpuid/  (only if it ends up re-exposing platform feature bits under a
             different name — worth avoiding if possible)

capability/ is depended on by:
  → reduce/  (associativity affects reduction strategy)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

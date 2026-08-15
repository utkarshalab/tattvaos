# lut — umath Lookup Table Infrastructure

**Module:** `lut/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Generic lookup-table construction and query helpers — distinct from the
purpose-built tables already baked directly into specific modules
(`dtype/dtype_meta.asm`'s 235-entry metadata table, `dtype/dtype_promote.asm`'s
235×235 promotion table). Those are hand-authored, dtype-specific tables;
`lut/` is meant to be the reusable machinery for building and querying a
lookup table in general — useful once other modules (a future
`math_fn` table-based trig implementation, `hash/`'s lookup structures)
need one without hand-rolling table-indexing code each time.

## Planned scope

- Generic fixed-stride table build/query (given element size and count)
- Interpolated lookup (for table-based approximations of transcendental
  functions — linear or higher-order interpolation between table entries)
- Perfect-hash or binary-search lookup for sparse/non-contiguous key
  ranges

## Dependencies (anticipated)

```
lut/ depends on:
  → memory/  (table storage/allocation)

lut/ is depended on by:
  → hash/          (hash table backing store)
  → math_fn/ (potentially)  (table-based trig, if that ends up faster
                               than the polynomial-series approach used
                               for exp/log/pow)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

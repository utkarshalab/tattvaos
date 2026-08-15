# compare — umath Generic Comparison Predicates

**Module:** `compare/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

dtype-generic comparison: given a `dtype_id` and two values (or bit
patterns), answer eq/lt/gt/three-way — including the IEEE-754 rules that
make naive comparison wrong (NaN compares false against everything
including itself, `-0.0 == 0.0`, total ordering for sorting needs
NaN/±0 placed somewhere deterministic). `scalar/`'s `min_f32`/`max_f32`
already embed a comparison for their own purposes; `compare/` is the
dtype-dispatched, general-purpose version `sort/` and `hash/`-adjacent
code need when the dtype isn't known until runtime.

## Planned scope

- `compare_eq/lt/gt/cmp3` dispatched by `dtype_id`
- IEEE-754-aware variants: `compare_eq_unordered_false` (NaN-propagating)
  vs. `compare_total_order` (NaN placed last, for stable sort)
- Array-level `compare_all_eq`, `compare_find_first_ne`

## Dependencies (anticipated)

```
compare/ depends on:
  → dtype/  (dispatch by dtype_id, traits for NaN/±0 handling)
  → bits/   (bit-pattern-level comparison for non-float dtypes)

compare/ is depended on by:
  → sort/  (comparator for dtype-generic sorting)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

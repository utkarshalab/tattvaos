# sort — umath Numeric Array Sorting

**Module:** `sort/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Sorting algorithms for numeric arrays, dtype-dispatched through
`compare/`'s comparison predicates: an introsort/quicksort-family general
sort, radix sort for fixed-width integer and float dtypes (radix sort on
IEEE floats needs the sign-bit-flip trick to make the bit pattern
monotonic — a `bits/`-level concern this module consumes rather than
reimplements), and argsort (return sorted indices rather than reordering
the data, needed when a caller has multiple parallel arrays to keep in
sync).

## Planned scope

- `sort_quicksort` / `sort_introsort` — general dtype-generic sort via
  `compare/`
- `sort_radix_u32/u64/f32/f64` — non-comparison sort for fixed-width types
- `sort_argsort` — indices rather than reordered values
- `sort_is_sorted` — cheap verification, useful in `assert/`-style checks

## Dependencies (anticipated)

```
sort/ depends on:
  → compare/  (dtype-generic comparison, total ordering for NaN placement)
  → bits/     (radix sort's monotonic bit-pattern transform for floats)
  → memory/   (scratch buffer for merge-based or out-of-place sorts)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# register — umath Custom dtype Registration

**Module:** `register/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose (best guess — the name is ambiguous without existing code)

`dtype/dtype_id.asm` reserves ID range `0xFF1–0xFFE` for user-defined
types (per `dtype/README.md`'s ID table), but the 235 built-in dtypes get
their family/size/traits/etc. from static compile-time tables. A
user-defined dtype has no static table entry — something has to let code
register a custom dtype's metadata (size, alignment, traits, cast rules) at
runtime so the rest of umath's dtype-dispatched functions can treat it like
any other type. `register/` is read as that mechanism: the dynamic
extension point for the static system `dtype/` otherwise is. Unlike the
`diag/`/`prefetch_strategy/`/`fpmode/`/`capability/` naming overlaps
resolved elsewhere in this sweep (each renamed away from a collision),
"register" doesn't collide with an existing module name — it's flagged as
a guess here because the *purpose* isn't otherwise inferable
from the name alone, not because of a collision.

## Planned scope (tentative)

- `register_dtype(id, size, align, traits, ...)` — populate a runtime
  table entry for a user-defined ID in the `0xFF1–0xFFE` range
- Runtime-side lookup that falls through to `dtype/`'s static tables for
  built-in IDs and this module's dynamic table for registered ones
- Validation that a registration doesn't collide with an already-taken ID

## Dependencies (anticipated)

```
register/ depends on:
  → dtype/  (extends the same ID space and metadata shape)

register/ is depended on by:
  → dtype/  (dtype_meta/dtype_support-style lookups need to check here too,
             for any ID in the user-defined range)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

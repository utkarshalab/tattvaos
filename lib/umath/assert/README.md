# assert — umath Runtime Invariant Checks

**Module:** `assert/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Debug-time invariant checking for the rest of umath: range checks, NaN/Inf
guards, alignment assertions, and similar "this should never happen"
checks that want to be free in release builds and loud in debug ones. Other
modules' `_verify` functions (`memory/arena.asm`'s `umath_arena_verify` and
siblings) are the self-check style already established elsewhere in this
tree; `assert/` is meant to be the shared mechanism those (and everything
else) build on, rather than every module inventing its own panic path.

## Planned scope

- Condition assertions (`assert_true`, `assert_eq_i32/i64/f32/f64` with an
  epsilon-aware float variant, `assert_range`)
- NaN/Inf/finite guards, shared rather than reimplemented per dtype
- A single panic/abort path other modules' assertions funnel into
- Compile-time (`%if`) or debug-build gating so checks compile out cleanly
  in a release kernel build

## Dependencies (anticipated)

```
assert/ depends on:
  → dtype/  (NaN/Inf checks are dtype-aware)

assert/ is depended on by:
  → every module with a _verify-style self-check
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

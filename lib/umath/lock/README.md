# lock — umath Locking Primitives

**Module:** `lock/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Spinlocks and simple mutexes for the shared mutable state umath's
allocators (`memory/pool.asm`, `memory/arena.asm`, etc.) and stats
counters need when accessed from more than one fiber/core. Built directly
on `atomic/`'s CAS primitive; this module is the spin-wait/backoff policy
around that primitive, not a reimplementation of it.

## Planned scope

- `spinlock_init/acquire/release/try_acquire`
- Backoff strategy (plain spin vs. `pause`-instruction backoff vs.
  exponential) — matters more once this runs on multiple cores contending
  for the same allocator
- A reader-writer variant, if `memory/`'s allocators end up needing
  concurrent-read/exclusive-write access patterns

## Dependencies (anticipated)

```
lock/ depends on:
  → atomic/  (CAS is the actual synchronization primitive)

lock/ is depended on by:
  → memory/  (allocators shared across fibers/cores)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# atomic — umath Atomic Memory Operations

**Module:** `atomic/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Lock-free primitives — compare-and-swap, fetch-and-add, atomic load/store
with explicit ordering — for the small amount of shared mutable state umath
itself needs (allocator free-lists, stats counters in `memory/stats.asm`,
eventually a lock-free variant of `memory/pool.asm`). This is a thin wrapper
over `lock cmpxchg`/`lock xadd`/fence instructions, not a general concurrency
framework; `thread/` is where higher-level thread-local/fiber-aware state
lives.

## Planned scope

- CAS: `atomic_cas32/64`, weak/strong variants
- Fetch-and-op: `atomic_fetch_add32/64`, `fetch_sub`, `fetch_or/and/xor`
- Load-acquire / store-release wrappers (x86-64's TSO makes most of these
  a plain mov, but the naming matters for portability and readability)
- Memory fences: `mfence`/`lfence`/`sfence` wrappers with clear semantics

## Dependencies (anticipated)

```
atomic/ depends on:
  → nothing (Tier 0, thin instruction wrappers)

atomic/ is depended on by:
  → memory/  (lock-free allocator variants, shared stats counters)
  → lock/    (spinlocks are built on CAS)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

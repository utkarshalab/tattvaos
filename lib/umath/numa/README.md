# numa — umath NUMA-Aware Allocation Hints

**Module:** `numa/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

NUMA-node-aware allocation hints for umath's own allocators
(`memory/arena.asm`, `memory/pool.asm`, etc.) on multi-socket hardware —
placing a math kernel's scratch buffers on the node local to the core
running it, rather than paying a remote-memory-access penalty on every
GEMM tile load. This is distinct from `hw/unuma/` in the repo's broader
hardware-abstraction tree (topology detection, distance matrix, general
memory affinity binding for the whole kernel) — `numa/` here is the thin,
math-workload-specific layer that consumes that topology information and
turns it into an allocation-site decision inside `memory/`.

## Planned scope

- Query the current core's NUMA node (via `hw/unuma/` once that exists)
- Node-local variants of `memory/arena.asm`'s init, or a node parameter
  threaded through the existing allocator
- A "spread across nodes" allocation mode for buffers too large to fit
  local to one node

## Dependencies (anticipated)

```
numa/ depends on:
  → hw/unuma/  (topology detection, outside umath)
  → memory/    (the allocators being made node-aware)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

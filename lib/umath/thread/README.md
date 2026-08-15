# thread — umath Thread/Fiber-Local State

**Module:** `thread/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Thread- and fiber-local state isolation for math workloads running under
TattvaOS's cooperative fiber scheduler (`kernel/sched/fiber.asm`,
`kernel/sched/sched.asm`): per-fiber scratch buffers, per-core allocator
instances, and similar state that must not be shared between concurrently-
running fibers without explicit synchronization through `lock/`. Distinct
from `lock/`, which is about protecting genuinely *shared* state —
`thread/` is about giving each fiber its own state so it doesn't need a
lock in the first place, which is the cheaper answer whenever it's
available.

## Planned scope

- Per-fiber scratch-buffer allocation (a small `memory/arena.asm` instance
  per fiber, sized for typical math-kernel scratch needs)
- Thread/fiber-local storage access pattern, tied to whatever
  `percpu_t`/`fcb_t`-shaped per-fiber state the kernel scheduler already
  exposes (see `kernel/sched/fiber.asm`)
- Work-stealing or partitioning helpers, if `gemm/`'s blocked kernel ends
  up wanting to split tile work across fibers

## Dependencies (anticipated)

```
thread/ depends on:
  → kernel/sched/  (fiber-local storage hooks into the scheduler's own
                     per-fiber control block)
  → memory/        (per-fiber scratch arena)

thread/ is depended on by:
  → gemm/  (if tile work ends up split across fibers)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

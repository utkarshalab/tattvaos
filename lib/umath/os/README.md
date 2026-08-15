# os — umath Kernel-Integration Glue

**Module:** `os/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

The seam between umath (which is otherwise deliberately freestanding — no
OS, no libc, no syscalls, as every other README in this tree states) and
the TattvaOS kernel it actually runs inside: hooking `memory/`'s allocators
into the kernel's own physical/virtual memory primitives when umath needs
more backing memory than its initial arena, registering with the fiber
scheduler for anything that wants to run as a background fiber (a `gemm/`
kernel large enough to want to yield partway through), and similar
integration points. Every *other* umath module stays pure computation with
no OS dependency; `os/` is deliberately the one place that's allowed to
know it's running inside TattvaOS specifically.

## Planned scope

- Backing-memory request hooks for `memory/arena.asm`/`region.asm` (page
  allocation from the kernel's physical allocator, once an arena
  exhausts its initial block)
- Fiber-yield integration for long-running math kernels (`gemm/`) that
  shouldn't monopolize a core past a scheduling quantum
- Nothing else in umath should `%include` kernel headers directly — this
  module is the boundary

## Dependencies (anticipated)

```
os/ depends on:
  → kernel/mem/, kernel/sched/  (the actual kernel primitives being bridged)

os/ is depended on by:
  → memory/  (backing allocation beyond the initial arena)
  → gemm/    (fiber-yield integration for long kernels)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS (except this module, by design)*

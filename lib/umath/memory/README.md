# memory — umath Memory Primitives

**Module:** `memory/`
**Tier:** 0–1 (depends on `bits/` for alignment checks only)
**Part of:** umath — unified math library

---

## Overview

`memory` is umath's own copy/set/compare/allocate layer — deliberately
separate from any kernel-wide `lib/mem` the rest of TattvaOS uses for
general allocation. Math workloads (tensors, matrices, large float arrays)
have access patterns and alignment requirements (cacheline, page, SIMD
width) that a general-purpose allocator doesn't need to specialize for, so
`gemm/`, `simd/`, and friends allocate and move memory through here rather
than through a generic kernel allocator.

---

## Files

```
memory/
├── copy.asm / move.asm / set.asm / zero.asm  ← memcpy/memmove/memset/
│                                                bzero, each with a plain,
│                                                SSE, AVX2, and (copy/set/
│                                                zero) AVX512 variant
├── compare.asm          ← memcmp, plain/SSE/AVX2
├── fill_pattern.asm     ← fill a buffer with a repeating 2/4/8/16-byte
│                           pattern (not just a single byte, unlike memset)
├── align.asm            ← align a pointer up to scalar/cacheline/page
│                           boundaries, is_aligned checks
├── prefetch.asm         ← software prefetch hints (T0/T1/T2/NTA/write),
│                           including a 2D block-transposed variant for
│                           matrix access patterns
├── arena.asm            ← bump allocator: init/alloc/alloc_zeroed/mark/
│                           rewind/reset, no individual free
├── pool.asm             ← fixed-size-block allocator: init/alloc/free/
│                           clear, O(1) alloc and free
├── slab.asm             ← slab allocator: init/alloc/free/reset, sits
│                           between arena (no free) and pool (fixed size)
├── region.asm           ← hierarchical arena: parent/child regions,
│                           free_all cascades to descendants
├── span.asm             ← a (pointer, length) view over an existing
│                           buffer: compare/copy/fill/find/split/subspan,
│                           no ownership or allocation of its own
└── stack_alloc.asm      ← LIFO allocator: alloc/free must nest, verify
                            checks the discipline held
```

`stats.asm` — allocation stats (current/peak/average, per-bin counts) —
sits at the bottom of the file list rather than beside a specific
allocator because it's meant to instrument whichever of the five
allocators above is active, not to be a sixth one.

---

## Calling convention

System V AMD64 ABI throughout:

```
rdi = dst, rsi = src, rdx = count   (copy/move/compare — memcpy shape)
rdi = buf, rsi = count               (set/zero/fill — memset shape)
rdi = allocator handle/state ptr     (arena/pool/slab/region/stack ops)
return                                rax = pointer or count, or 0/1 bool
```

Every allocator here (`arena`, `pool`, `slab`, `region`, `stack_alloc`)
takes an explicit state pointer rather than using a global — umath has no
notion of "the" allocator, callers own their arena/pool/slab instance and
pass it in, same as everything else in a freestanding kernel context with
no hidden global state.

---

## Design notes

**Five allocators, not one configurable one.** Arena (bump, no free), pool
(fixed-size blocks, O(1) free), slab (variable within a size class), region
(hierarchical arena with cascading free), stack (LIFO, nesting enforced).
Math workloads have genuinely different lifetime shapes — a GEMM
scratch buffer wants arena/bump, an operator staging pool wants fixed-size
pool — so this picks explicit allocators over one generic one with modes.

**`span` owns nothing.** Every other type in this file allocates memory;
`span` is a bounds-checked view over memory someone else owns, closer to
how `bits/`'s buffer-taking functions treat their input than to an
allocator. It's here rather than in `bits/` because its operations
(compare/copy/fill/find) are memory operations, not bit ones.

**Instruction-set tiers are separate functions, not runtime dispatch (yet).**
`memcpy`/`memcpy_sse`/`memcpy_avx2`/`memcpy_avx512` are four distinct
exported symbols. Feature-detection dispatch belongs to `cpuid/` once that
module exists; until then, callers pick the variant they know their target
supports.

---

## Dependencies

```
memory/ depends on:
  → bits/  (alignment checks: is_aligned, align_up/down)

memory/ is depended on by:
  → gemm/, simd/, tensor-shaped modules  (scratch buffers, staging pools)
  → dtype/  (alignment info feeds allocation decisions)
  → every module that allocates or moves bulk data
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

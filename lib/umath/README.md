# lib/umath — Math Library

> Math primitives for Tattva OS, optimized for AI workloads.

Pure x86-64 assembly. No libc, no libm, no OS dependency (except `os/`,
deliberately the one seam that's allowed to know it's running inside
TattvaOS — see `os/README.md`). Every function follows System V AMD64 ABI.
Built the same way every other TattvaOS subsystem is: one module at a time,
file-by-file, to production depth, rather than breadth-first stubs.

Part of the `lib/` category in Tattva OS.

---

## Status

Four modules have real, numerically-verified implementations:

```text
bits/     Tier 0   fixed-width integer & IEEE-754 bit-pattern primitives
memory/   Tier 0-1  copy/set/compare/allocate (5 allocator shapes)
scalar/   Tier 0-1  abs/min/max/clamp/round/sign/reciprocal, i32/i64/f32/f64
dtype/    Tier 0    235-type classification/metadata system
math_fn/  Tier 1    sqrt/exp/log/pow/sin/cos/tan/hypot, f32/f64 — the full
                     transcendental math set
```

Every other directory listed below is scaffolded (created, named, given a
README describing its intended purpose) but not yet implemented. Per this
project's sweep workflow, an empty module is "not yet swept," not broken —
see each module's own README for what it's expected to hold and what it
depends on once its turn comes.

```text
assert/  atomic/  cache/  capability/  compare/  compress/  convert/
cpuid/  diag/  format/  fpmode/  gemm/  hash/  histogram/  lock/  lut/
norm/  numa/  os/  perf/  prefetch_strategy/  profile/  random/
reduce/  register/  simd/  sort/  stability/  stats/  tests/  thread/
time/
```

Four modules (`diag/`, `prefetch_strategy/`, `fpmode/`, `capability/`)
were originally scaffolded as `log/`, `prefetch/`, `round/`, `traits/`,
each of which collided with something that already existed elsewhere in
the tree (`math_fn/log_f32.asm`, `memory/prefetch.asm`,
`scalar/round_f32.asm`, `dtype/dtype_traits.asm` respectively). Renamed to
remove the ambiguity rather than carry two same-named things side by side
— each module's own README notes the rename and why.

---

## A note on the single-translation-unit build

Per `boot/Makefile`, the entire kernel — including everything under
`lib/`, so all of umath — assembles as **one** NASM translation unit:
`kernel/entry.asm` pulls in every other file via `%include`. That means
every non-local label anywhere in this tree, including a file's own
`.rodata` constants, must be globally unique — NASM has no file-private
symbol concept the way C has `static`. This bit a real, cross-cutting bug
during development (10 groups of colliding constant names like
`const_one_f32` across 20 files) before it was fixed; every file in this
tree now prefixes its local constants with the file's own name
(`sqrtf32_half`, not `const_half`). Keep that convention for anything new.

---

## Verification methodology

Every implemented function in `math_fn/` (and, going forward, every module
with actual numerical content — `norm/`, `stats/`, `gemm/`) is checked two
ways before being considered done:

1. **Syntax**: `nasm -f elf64` under WSL.
2. **Numerics**: `ld -shared` the object into a `.so`, load it from Python
   via `ctypes`, and compare against a reference implementation (Python's
   `math` module) across a wide range of inputs including domain edges
   (zero, negative, NaN, Inf, subnormal). No C compiler needed — the build
   environment doesn't have one, and this path doesn't require one either.

This isn't optional polish. It's what caught every real bug that shipped
during `math_fn`'s development: two register-clobber bugs, two
alignment-fault crashes, three NaN-propagation bugs, and one accuracy bug
from a precision-losing constant — none of which nasm's own syntax check
would ever have flagged, several of them recurring instances of the same
mistake caught by re-running the same class of check on new files. See
`math_fn/README.md` for the specifics.

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# lib/umath — Math Library

> Math primitives for Utkarsha OS, optimized for AI workloads.

Pure x86-64 assembly. No libc, no libm, no OS dependency (except `os/`,
deliberately the one seam that's allowed to know it's running inside
Utkarsha OS — see `os/README.md`). Every function follows System V AMD64 ABI.
Built the same way every other Utkarsha OS subsystem is: one module at a time,
file-by-file, to production depth, rather than breadth-first stubs.

Part of the `lib/` category in Utkarsha OS.

---

## Status

Eight modules have real, numerically-verified implementations (checked by
`tests/run_tests.sh`, see below):

```text
bits/     Tier 0   fixed-width integer & IEEE-754 bit-pattern primitives
memory/   Tier 0-1  copy/set/compare/allocate (5 allocator shapes)
scalar/   Tier 0-1  abs/min/max/clamp/round/sign/reciprocal, i32/i64/f32/f64
dtype/    Tier 0    213-type classification/metadata system
math_fn/  Tier 1    sqrt/cbrt, exp/exp2/exp10/expm1, log/log2/log10/log1p,
                     pow, sin/cos/tan, hypot, scalbn; f32/f64 + arrays
stability/ Tier 1   compensated/pairwise sums, Welford mean/variance,
                     log-sum-exp
reduce/   Tier 1    sum/mean, dot/sum of squares, overflow-safe product,
                     exact integer sums
cpuid/    Tier 0    CPU feature detection + SSE2 fallbacks for every
                     faster instruction (umath runs on any x86-64 CPU)
```

Every other directory listed below is scaffolded (created, named, given a
README describing its intended purpose) but not yet implemented. Per this
project's sweep workflow, an empty module is "not yet swept," not broken —
see each module's own README for what it's expected to hold and what it
depends on once its turn comes.

```text
assert/  atomic/  cache/  capability/  compare/  compress/  convert/
diag/  format/  fpmode/  gemm/  hash/  histogram/  lock/  lut/
norm/  numa/  os/  perf/  prefetch_strategy/  profile/  random/
register/  simd/  sort/  stats/  tests/  thread/  time/
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

The kernel assembles as **one** NASM translation unit: `kernel/entry.asm`
pulls in every other file via `%include` (`boot/Makefile` only lists the
rest of `lib/` as rebuild prerequisites). umath is not `%include`d there
yet, so nothing in the kernel calls it today; `tests/run_tests.sh`
assembles every umath file on its own and all of them as one unit, so the
tree stays ready for that. Files that call into another file
`%include` it with a repo-root path (`%include "lib/umath/math_fn/log_f64.asm"`)
behind the usual include guards, so each one assembles standalone too.

Because of the single translation unit, every non-local label anywhere in
this tree, including a file's own `.rodata` constants, must be globally
unique — NASM has no file-private
symbol concept the way C has `static`. This bit a real, cross-cutting bug
during development (10 groups of colliding constant names like
`const_one_f32` across 20 files) before it was fixed; every file in this
tree now prefixes its local constants with the file's own name
(`sqrtf32_half`, not `const_half`). Keep that convention for anything new.

---

## Verification methodology

`sh lib/umath/tests/run_tests.sh` (Linux/WSL: nasm, ld, python3) checks
every implemented module three ways:

1. **Assembly**: `nasm -f elf64` on every file standalone and on all of
   them as one translation unit, with `-Werror=number-overflow` and
   `-Werror=other`. Those two warning classes are not cosmetic in this tree:
   a 64-bit immediate in `cmp reg, imm` is silently truncated to a
   sign-extended 32 bits (it broke every allocator's magic check), and
   initialized data in `.bss` is silently dropped (it zeroed a cache whose
   "not computed" sentinel was 0xFF).
2. **Behaviour**: `ld -shared` the unit into a `.so`, load it from Python
   via `ctypes`, and compare against reference implementations (Python's
   `math` module, Python integers, byte strings) across a wide range of
   inputs including domain edges (zero, negative, NaN, Inf, subnormal).
   No C compiler needed — the build environment doesn't have one, and this
   path doesn't require one either.
3. **Older CPUs**: the behaviour tests run a second time with
   `UMATH_CPU_MASK=0`, which limits umath to the x86-64 baseline (SSE2) so
   every SSE4/AVX/BMI fast path takes its fallback, and `test_cpu.py`
   compares the fallbacks with the native instructions bit for bit. See
   `cpuid/README.md`.

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

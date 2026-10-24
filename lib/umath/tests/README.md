# tests — umath Test Harness

**Module:** `tests/`
**Status:** Implemented — covers bits/, cpuid/, dtype/, geom/, math_fn/, memory/, random/, reduce/, scalar/, stability/.
**Part of:** umath — unified math library

---

## Purpose

Test harness and test cases for umath. `boot/Makefile` explicitly excludes
every `tests/` directory (`-not -path '*/tests/*'`) from the kernel's
source glob — this directory is never assembled into `kernel.bin`, it has
its own separate build/run path, matching every other `tests/` directory
already established elsewhere in the repo (`unet/`, `crypto/`, etc. per
`boot/Makefile`'s comment on the subject).

## Running

```
sh lib/umath/tests/run_tests.sh
```

Needs nasm, ld and python3 on the host (Linux/WSL); no QEMU and no C
compiler. Exit status 0 means everything passed.

## What it checks

- `run_tests.sh` assembles every `.asm` file in the implemented modules on
  its own and all of them as one translation unit, with
  `-Werror=number-overflow -Werror=other` (see `../README.md` for why
  those two warning classes matter here), links the unit into a shared
  object, then runs each `test_*.py` against it twice: natively, then
  with `UMATH_CPU_MASK=0` so umath uses only the SSE2 baseline and every
  SSE4/AVX/BMI fast path goes through its fallback (`../cpuid/`).
- `test_math_fn_ext.py`: the extended math_fn functions (exp2, exp10,
  expm1, log2, log10, log1p, cbrt, scalbn, atan, atan2, asin, acos,
  sinh, cosh, tanh, asinh, acosh, atanh). It covers:
  - ULP sweeps over each domain;
  - special values, including atan2's full signed-zero/Inf table;
  - the exactness promises: exp2/log2 of powers of two, exp10/log10 of
    10^0..10^22, cbrt of perfect cubes;
  - array/inplace bit for bit against the scalar.
  `UMATH_VERBOSE=1` prints the measured worst case per function.
- `test_ieee.py`: the IEEE 754 helpers (fmod, remainder, remquo,
  frexp, ilogb, logb, modf, nextafter/nextup/nextdown, fdim,
  scalbn_f32/ldexp_f32, fma), each bit for bit against an exact
  reference. Under `UMATH_CPU_MASK=0` the fma checks run the software
  path.
- `test_math_fn.py`: ULP sweeps against Python's `math` module, special
  values (NaN, ±Inf, ±0, overflow/underflow), the sin/cos domain bound, and
  array/inplace variants against the scalar routine.
- `test_memory.py`: fuzzed copy/move (with overlap)/set/zero/compare/fill
  against Python byte strings, return values, and every allocator
  operation after init.
- `test_scalar.py`: rounding, abs/neg/sign, min/max/clamp, reductions
  (including NaN propagation) and array/inplace variants.
- `test_bits.py`: property tests against Python integers, including 128- and
  512-bit shifts, buffer bit insertion and buffer rotation.
- `test_dtype.py`: classification consistency for every id in
  `dtype_id.asm`, promotion (commutativity and the table in
  `dtype/README.md`), support levels, value traits, ULP and validation.
- `test_reduce.py`: sum/mean, dot/sum of squares and products against
  exact `Fraction` references (including products whose intermediates
  overflow, subnormal results and special values), and exact integer sums
  at each type's extremes.
- `test_stability.py`: Kahan and pairwise sums against `math.fsum`
  (including cancellation and 1e6-term sums), Welford mean/variance
  against exact `Fraction` arithmetic (large offsets, chunked + merged),
  log-sum-exp accuracy and special values.
- `test_cpu.py`: CPU detection against the host's reported CPU flags,
  the restrict/has API, and the SSE2 fallbacks bit for bit against the native instructions
  (a second library copy restricted to the baseline; sin/cos/exp/pow and
  every floor/ceil/round/trunc form, on raw bit patterns including
  signalling NaNs).
- `umath_ref.py`: shared helpers (ULP distance, float32 rounding, a small
  failure collector). `load()` applies `UMATH_CPU_MASK` when it is set.

Every variant runs on every host: the AVX2/AVX-512 ones fall back to
narrower code when the CPU lacks them. They are only *native* on hardware
that has the extension, though; on this machine (no AVX-512) the
`_avx512` routines are tested through their AVX2 fallback.

## Dependencies

```
tests/ is excluded from the kernel image entirely (see boot/Makefile);
it depends on whatever host toolchain (nasm, ld, a Python or similar
driver) is available in the development environment, not on anything
inside the kernel build.
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

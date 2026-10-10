# tests — umath Test Harness

**Module:** `tests/`
**Status:** Implemented — covers bits/, dtype/, math_fn/, memory/, reduce/, scalar/, stability/.
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
  object, then runs each `test_*.py` against it.
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
- `umath_ref.py`: shared helpers (ULP distance, float32 rounding, a small
  failure collector).

AVX2 variants are skipped on a host without AVX2; the AVX-512 variants
are not exercised (no hardware to run them on).

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

# math_fn — umath Transcendental Math

**Module:** `math_fn/`
**Tier:** 1 (depends on `dtype/` for type conventions only; no other umath module)
**Part of:** umath — unified math library

---

## Overview

`math_fn` implements the actual "libm" of umath: the transcendental functions
(`sqrt`, `exp`, `log`, `pow`, `sin`/`cos`/`tan`, `hypot`) that every higher-
level module — `norm`, `stats`, `gemm`'s activation paths,
softmax — is ultimately built from. Everything here is hand-written x86-64
assembly implementing its own range reduction and polynomial/series
approximation; there is no libc, no libm, and nothing is linked in from an
external math library. Algorithms follow the same *shape* as fdlibm/Cephes-
derived libm implementations (range-reduce, evaluate a minimax or Taylor
series on the reduced argument, reconstruct via IEEE-754 bit manipulation)
but every coefficient and bound here was independently derived and
numerically verified, not transcribed from another codebase.

---

## Files

```
math_fn/
├── sqrt_f32.asm / sqrt_f64.asm   ← exact (hardware sqrtss/sqrtpd) + fast
│                                    approx/refined (Newton-Raphson on
│                                    rsqrt) + array/inplace variants
├── exp_f32.asm / exp_f64.asm     ← e^x via range reduction (k = round(x /
│                                    ln2), r = x - k*ln2 split hi/lo) +
│                                    polynomial on r + 2^k applied as two
│                                    halves built directly from IEEE-754
│                                    bits (overflow → +Inf, gradual
│                                    underflow → 0)
├── log_f32.asm / log_f64.asm     ← ln(x) via IEEE-754 bit decomposition
│                                    (x = m·2^k) + atanh series on
│                                    s = f/(2+f), f = m-1; f64 regrouped
│                                    so the leading f is exact
├── pow_f32.asm / pow_f64.asm     ← x^y = exp(y·ln(x)), plus the IEEE
│                                    special cases and a negative-base
│                                    integer-exponent path exp/log alone
│                                    can't cover; pow_f32 widens to double
│                                    and calls pow_f64
├── sin_f32.asm / sin_f64.asm     ← quadrant range reduction (n = round(x
│                                    * 2/pi), r = x - n*(pi/2) with pi/2
│                                    split 21+21+53 bits) + Taylor series
│                                    on sin(r) and cos(r), by n mod 4
├── cos_f32.asm / cos_f64.asm     ← same reduction as sin, cosine's
│                                    quadrant table
├── tan_f32.asm / tan_f64.asm     ← sin(x)/cos(x), composed from the two
│                                    above rather than its own reduction
├── hypot_f32.asm / hypot_f64.asm ← sqrt(x^2+y^2) via a = max(|x|,|y|),
│                                    hypot = a*sqrt(1+(b/a)^2) — overflow/
│                                    underflow-safe, composed from sqrt
├── exp2_f32.asm / exp2_f64.asm   ← 2^x = 2^k * e^(r*ln2), k = round(x),
│                                    r = x - k exact
├── exp10_f32.asm / exp10_f64.asm ← 10^x = 2^k * e^(r*ln10), r from a
│                                    hi/lo split of log10(2); 10^0..10^22
│                                    exact
├── expm1_f32.asm / expm1_f64.asm ← e^x - 1 with Kahan's correction
│                                    (u-1)*x/log(u)
├── log2_f32.asm / log2_f64.asm   ← e + ln(m)*log2(e) on the exact split
│                                    x = m*2^e; log2(2^k) exact
├── log10_f32.asm / log10_f64.asm ← same split, e*log10(2) as exact hi
│                                    + lo; log10(10^0..10^22) exact
├── log1p_f32.asm / log1p_f64.asm ← log(u)*x/(u-1), u = 1+x (Goldberg)
├── cbrt_f32.asm / cbrt_f64.asm   ← exact reduction to [1,8), bit-trick
│                                    seed, Newton, one double-double
│                                    residual correction
├── scalbn_f64.asm                ← x*2^n (scalbn/ldexp), one rounding
├── atan_f32.asm / atan_f64.asm   ← fold to [0,1], shift by the nearest
│                                    of 4 anchors, 10-term series on
│                                    |t| <= tan(pi/24); shared core
├── atan2_f32.asm / atan2_f64.asm ← full IEEE quadrant/zero/Inf table on
│                                    top of the atan core
├── asin_f32.asm / asin_f64.asm   ← atan(a / sqrt((1-a)(1+a)))
├── acos_f32.asm / acos_f64.asm   ← 2*atan(sqrt((1-x)/(1+x)))
├── sinh_f32.asm / sinh_f64.asm   ← expm1-based below 22, e^a/2 above,
│                                    (w/2)*w near overflow
├── cosh_f32.asm / cosh_f64.asm   ← e/2 + 1/(2e), same large-a handling
├── tanh_f32.asm / tanh_f64.asm   ← t/(t+2), t = expm1(2a); 1 from 22
├── asinh_f32.asm / asinh_f64.asm ← log1p / log forms by range,
│                                    ln(a)+ln2 for huge a
├── acosh_f32.asm / acosh_f64.asm ← log1p(t + sqrt(2t+t^2)), t = x-1
│                                    exact, near 1
├── atanh_f32.asm / atanh_f64.asm ← log1p(2a/(1-a))/2, small-a form
└── loops.asm                     ← macros: array/inplace loops and the
                                     f32-through-f64 wrappers
```

---

## Design decisions, and why

**exp overflows to +Inf and underflows to 0, branch-free.**
`exp_f32`/`exp_f64` clamp their input to a range just past the true
overflow/underflow points (`[-104, 89]` / `[-746, 710]`), then apply `2^k`
as `2^(k>>1) * 2^(k - (k>>1))`. Both halves are normal numbers, so the first
multiply is exact and the second rounds once: results beyond the format's
maximum become `+Inf`, tiny results round through subnormals to `0`, and
there is still no branch on the hot path. The clamp is written with the
constant as `minss`/`maxss`'s *first* operand, because those instructions
return their second operand when either input is NaN — the other way round
turns NaN into a large finite number. An earlier version saturated to the
largest/smallest *normal* value instead (exp(1000) = 8.99e307,
exp(-1000) = 2.2e-308) and returned a finite number for NaN.

**pow_f32 is evaluated in double.**
`exp(y·ln(x))` amplifies log's relative rounding error by `|y·ln(x)|`, so a
single-precision pow lost ~200 ULP on results near `1e33`. `pow_f32` now
widens both arguments, calls `pow_f64`, and rounds once; the special cases
carry over unchanged. `pow_f64` itself still carries this amplification
(measured up to ~1.4e3 ULP for results near `1e239`); removing it would need
an extended-precision log.

**Array paths are packed and bit-identical to the scalar routines.**
`exp`, `log`, `sin`, `cos`, `tan`, `pow` and `hypot` run their array paths
2 lanes (f64) or 4 lanes (f32) at a time with the scalar algorithm's exact
operation sequence: per-lane packed arithmetic rounds exactly like the
scalar instruction, integer exponent adjustments become exact
double/integer lane operations, the trig quadrant is computed exactly as
`n - 4*floor(n/4)`, and domain cases (NaN, ±0, negatives, ±Inf, the trig
size bound) are blended in at the end with the scalar's own constants.
`tests/test_math_fn.py` checks every lane bit-for-bit against the scalar
call over the whole domain. sin/cos/tan share one reduction core per
width (`sinf64__core2`, `sinf32__core4`); tan takes both sin and cos from a
single pass of it. `pow` evaluates `exp(y * ln|x|)` on every lane with
the packed log and exp, then applies the scalar's special cases as lane
masks in reverse priority (so the case the scalar tests first wins);
`pow_f32` widens pairs into the f64 core, as the scalar does. Measured on
1e6-element arrays: log/sin/cos 2-3x faster (f64) and ~5x (f32), tan
3.8x / 6.6x, pow 1.8x, hypot 2.2x / 4.2x; `sqrt` maps to the hardware
instruction.

**Subnormal inputs are explicitly handled in `log`.**
The IEEE-754 bit-decomposition `log` relies on assumes an implicit
leading-1 mantissa bit, which subnormals don't have. Both `log_f32` and
`log_f64` detect input below the normal-range floor, scale it up by an
exact power of two first, and correct the reconstructed exponent afterward.
This was found by testing at the exponent floor, not by inspection — worth
remembering if a similar bit-decomposition trick shows up elsewhere in
`convert/` or `norm/`.

**sin_f32/cos_f32 reduce in double precision, then narrow.**
Both take an `f32` argument but widen it to `f64` (`cvtss2sd`) before the
range-reduction multiply/subtract, and only narrow the reduced argument
back to `f32` (`cvtsd2ss`) for the polynomial evaluation. A first version
that did the whole reduction in single precision was measurably wrong
(~1.7e-5 absolute error) by `x=1000` — not an extreme input, just large
enough that a float32-rounded copy of the pi/2 split had already lost
the "n·p1 stays exact" property the split exists for. This is the standard
fix real `sinf`/`cosf` implementations use, not an original technique.

**Three-part pi/2 split, and a hard domain bound.**
pi/2 is split as p1 + p2 + p3 with 21, 21 and 53 significant bits, so `n·p1`
and `n·p2` are exact while `n < 2^32`, i.e. `|x| < 2^32 * pi/2 ≈ 6.7e9`.
Measured against a 60-digit reference, the absolute error stays at 1.1e-16
up to `|x| = 6.5e9`; beyond that the simple (not Payne-Hanek) reduction
degrades roughly as `|x| * 1e-16`, and for `|x| >= 2^52`, where it means
nothing, sin/cos return NaN instead of an out-of-range value. The quadrant
`n mod 4` is taken from a 64-bit conversion: a 32-bit one returns
`0x80000000` once `n >= 2^31` and picked the wrong quadrant from `|x| ≈ 3.4e9`.

**tan composes sin+cos instead of its own reduction.**
Same reasoning as `pow` composing `log`+`exp`: sin/cos are already
verified, and hardware `divss`/`divsd` already does the IEEE-correct thing
for `cos(x)` near zero (produces a very large result, or a signed `Inf` for
exact zero — the correct limiting behavior at tan's vertical asymptotes)
without any special-casing needed here.

**hypot's array signature takes two input arrays, like pow's.**
`rdi=dst, rsi=xs, rdx=ys, rcx=count` — and like `pow_f32_array`/
`pow_f64_array`, its loop counter has to live somewhere `log`/`exp`/`sqrt`
(reached transitively) won't clobber. `sqrt` alone doesn't touch any GPR
in its scalar form, so `hypot_f32_array`/`hypot_f64_array` keep `rcx` as
the counter directly rather than needing `pow`'s `r10` workaround — but
that's an property of what `sqrt` happens not to touch, not a general
rule; re-check this per callee, don't assume it.

**Every constant name is unique per file.**
NASM has no file-private symbol concept, and this whole tree is meant to be
`%include`d into the kernel's single translation unit (`kernel/entry.asm`;
umath isn't included there yet, but `tests/run_tests.sh` assembles it all as
one unit). A generic name like `const_one_f32` declared in two
different files is a silent build-breaker the moment both get pulled in —
it doesn't fail until integration, long after the file that introduced it
looked finished. Every constant here is prefixed with its file's own name
(`sqrtf32_half`, `logf64_inv23`, ...) for exactly this reason.

---

**The extended functions reduce exactly, then reuse exp and log.**
`exp2`, `exp10`, `expm1`, `log2`, `log10` and `log1p` do their range
reduction with no rounding error at all, then call `umath_exp_f64` or
`umath_log_f64` only on a small argument:
- `exp2`: `x - round(x)` is exact.
- `exp10`: log10(2) is split so that `k*hi` is exact.
- `log2`/`log10`: the exponent is read straight from the bits.
- `expm1`/`log1p`: Kahan's and Goldberg's corrections cancel the rounding
  of `exp(x)` and of `1 + x`, so tiny arguments keep full relative
  accuracy.

The naive forms (`exp(x*ln2)`, `log(x)/ln(2)`, `exp(x) - 1`,
`log(1 + x)`) lose up to hundreds of ULP, or all digits, in the same
places.

Their errors are therefore those of the exp/log cores plus about one
rounding. Measured against 50-digit references: exp2 1.15, exp10 1.37,
log2 1.44, log10 1.72, expm1 1.89, log1p 1.90 ULP.

**The f64 log core keeps its leading term exact.**
`umath_log_f64` used to evaluate `2*s*(1 + s^2/3 + ...) + k*ln2` with
`s = (m-1)/(m+1)`. The rounded division and the rounded `k*ln2` both
reached the result at full weight, which cost ~3 ULP. It now uses the
same atanh series regrouped:

    f = m - 1 (exact),  s = f/(2+f),  hfsq = f^2/2
    ln(x) = k*ln2_hi - ((hfsq - (s*(hfsq + R(s^2)) + k*ln2_lo)) - f)

- The large term `f` is exact and only small corrections round.
- ln(2) is split so that `k*ln2_hi` is exact.
- The measured worst case drops to 0.78 ULP.

Every function built on log improved with it: log2, log10, log1p, expm1,
pow, and the hyperbolics below. The packed array path changed in
lockstep and is still bit-identical per lane.

**Inverse trig shares one atan core.**
`atanf64__core` works on `a >= 0`:
1. Fold `a > 1` to `1/a` (using `pi/2 - atan(1/a)`).
2. Shift by the nearest anchor `T` in {0, tan(pi/12), tan(pi/6), 1},
   with `t = (a - T)/(1 + a*T)`. This leaves `|t| <= tan(pi/24)`, where a
   10-term series converges fully.
3. Rebuild as `H + (L + atan(t))`. The hi/lo pair `H + L` is `atan(T)`,
   or `pi/2 - atan(T)` when folded, computed from the double `T` itself,
   so the identity is exact for the anchor actually stored.

On top of the core:
- `asin` uses `atan(a / sqrt((1-a)(1+a)))`; `1 - a` is exact near 1.
- `acos` uses `2*atan(sqrt((1-x)/(1+x)))`, which is cancellation-free at
  both ends.
- `atan2` applies the IEEE signed-zero/Inf table before calling the core.

Measured worst cases: atan 1.19, acos 1.77, asin 2.24 ULP; atan2 1 ULP
against Python.

**The hyperbolics never subtract nearly equal exponentials.**
- `sinh` and `tanh` go through `expm1`: `(t + t/(t+1))/2` and `t/(t+2)`.
- `cosh` adds two positive terms.
- `asinh`, `acosh` and `atanh` use `log1p` of exactly formed arguments
  near their zeros, and switch to `ln(a) + ln2` where `2a` could
  overflow.
- Near the overflow edge, `sinh` and `cosh` use `(w/2)*w` with
  `w = e^(a/2)`, which stays finite up to the true limit (~710.48).

Measured worst cases: cosh 1.26, sinh 2.06, asinh 2.24, atanh 2.32,
acosh 2.47, tanh 2.67 ULP.

**cbrt is nearly correctly rounded.**
- An exact reduction to `[1, 8)` keeps every intermediate normal.
- Four Newton steps from a bit-trick seed reach ~2-3 ULP.
- The residual `a - y^3` is then computed in double-double (Dekker
  products, no FMA needed), and one last correction brings the result to
  0.50 ULP measured; perfect cubes come out exact.

Python's own `math.cbrt` was measured 3 ULP off on the same inputs, so
the tests compare against an exactly rounded reference built from
`Fraction`.

**The f32 versions are evaluated in double.**
The new f32 functions widen to double, call the f64 routine and round
once. Widening is exact, so they are within one f32 ULP (the tests
measure 0 on their inputs), and they share every special case with the
f64 routine.

**Array loops come from one macro.**
The new functions' `_array`/`_inplace` variants are generated by
`loops.asm`. It keeps the pointers and count in callee-saved registers,
which rules out the clobbered-loop-counter bug described below by
construction. These loops are scalar per element; packed versions, like
log/exp/sin have, are a later optimisation.

## Calling convention

System V AMD64 ABI throughout:

```
f32 args   → xmm0, xmm1 (scalar)
f64 args   → xmm0, xmm1 (scalar)
array args → rdi = dst, rsi = src, rdx = count   (single-array functions)
           → rdi = dst, rsi = xs, rdx = ys, rcx = count   (pow, hypot: two
                                                             input arrays)
return     → xmm0 (scalar result)
```

Register-safety note: several scalar routines in this module use `ecx`/`rcx`
or `r8`/`r9` as internal scratch (bit-field extraction, subnormal-scale
flags). Any array/inplace loop that calls into another `math_fn` routine
must not keep its own loop counter in a register that routine clobbers —
`pow_f32_array`/`pow_f64_array` specifically move their count out of `rcx`
into `r10` before looping, because `log_f32`/`log_f64` (reached transitively
through `pow`) use `ecx`/`rcx` internally. This was a real, silent bug
during development (corrupted loop counter, not a crash until the second
iteration touched out-of-bounds memory) — check what a callee clobbers
before assuming a loop-carried register survives a `call`.

---

## Verification

Every function in this module is checked against a reference
implementation (Python's `math` module, IEEE double throughout) via an
`ld -shared` + `ctypes` harness — no C compiler needed, since the kernel
toolchain doesn't have one. The harness is checked in: run
`sh lib/umath/tests/run_tests.sh` (see `tests/README.md`). Measured worst
cases: sqrt 0 ULP, exp ≤ 1 ULP, log ≤ 1 ULP (f64; f32 ≤ 3), sin/cos ≤ 2
ULP, tan ≤ 3 ULP, hypot ≤ 2 ULP; pow_f64 as described above. The extended
functions are checked by `tests/test_math_fn_ext.py` against Python's
`math` (the bounds include its own error):
- exp2, exp10, log2, atan, acos, cosh: 2 ULP;
- expm1, log10, log1p, asin, sinh, tanh, asinh, acosh, atanh, atan2:
  3 ULP;
- cbrt: 1 ULP;
- every f32 function: 1 ULP;
- scalbn: exactly against ldexp.

Bugs this process actually caught (kept here so the pattern is recognizable
next time, not as a changelog):
- Two register-clobber bugs (`log_f32`, `log_f64`): a scalar routine's own
  scratch register aliased its caller's array-loop counter.
- Two alignment faults (`pow_f32`, then `sin_f32` independently): `xorps`
  needs a 16-byte-aligned 128-bit memory operand; a constant smaller than
  16 bytes, or one not given its own `align 16`, crashes instead of just
  being wrong. Hit twice — a tree-wide grep for
  `(xorps|xorpd|andps|andpd|movaps|movapd)\s+\w+,\s*\[` plus manual
  alignment inspection is worth running on any *new* file that touches a
  128-bit constant, not just trusting the pattern was learned the first
  time.
- Three NaN-propagation bugs (`pow_f32`, `pow_f64`, then `hypot_f32`/
  `hypot_f64` independently): `ucomiss`/`ucomisd` set ZF=1 for both
  "equal" and "unordered" (NaN) — a `je` right after one without a `jp`
  guard first silently treats NaN as equal. Hit three times total across
  this module; a tree-wide scan for `ucomis[sd]` immediately followed by
  `je`/`jz` with no `jp` in between is worth running on any new file with
  a NaN/special-value check, and manually confirming each hit is either a
  real bug or already downstream of an unconditional `jp` earlier in the
  same function (most were, by the third scan — false positives are
  expected once NaN has already been excluded upstream).
- One accuracy bug found by testing a "boring" input, not an edge case
  (`sin_f32`/`cos_f32`, `x=1000`): a hi/lo split constant computed for
  double precision but declared as a single-precision `dd` silently loses
  the exactness property the split exists for. Fixed by doing range
  reduction in double and narrowing only the small reduced argument back
  to float32.
- Two constants computed in double instead of exactly (`sin`/`cos` pi/2
  low part, `exp_f64` ln2 low part): `lo = double(pi/2) - hi` carries
  double(pi/2)'s own rounding error (6e-17), so the hi/lo split bought
  nothing — sin_f64 was off by 13,554 ULP near 3·pi and exp_f64 by 209 ULP.
  Compute split constants with exact (rational/decimal) arithmetic.
- `minss`/`minsd`/`maxss`/`maxsd` return the *second* operand on NaN: a
  clamp written `minsd x, [limit]` returns the limit for NaN x, and a
  reduction loop `minsd acc, x` lets a NaN element reset the accumulator
  (`min([1, NaN, 3])` returned 3).

---

## Dependencies

```
math_fn/ depends on:
  → nothing at runtime (each file is self-contained except:
    pow_f64 calls log_f64 and exp_f64, pow_f32 calls pow_f64;
    tan_f32/f64 call sin_f32/f64 and cos_f32/f64;
    hypot_f32/f64 call sqrt_f32/f64 — all from this same directory)

math_fn/ is depended on by:
  → norm/, stats/, gemm/ (activation functions, softmax, normalization)
  → every module that needs a transcendental function
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

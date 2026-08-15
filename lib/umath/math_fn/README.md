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
│                                    polynomial on r + 2^k reconstructed
│                                    directly from IEEE-754 bits
├── log_f32.asm / log_f64.asm     ← ln(x) via IEEE-754 bit decomposition
│                                    (x = m·2^k) + atanh series on
│                                    s=(m-1)/(m+1)
├── pow_f32.asm / pow_f64.asm     ← x^y = exp(y·ln(x)), plus the IEEE
│                                    special cases and a negative-base
│                                    integer-exponent path exp/log alone
│                                    can't cover
├── sin_f32.asm / sin_f64.asm     ← quadrant range reduction (n = round(x
│                                    * 2/pi), r = x - n*(pi/2) split
│                                    hi/lo) + Taylor series on sin(r) and
│                                    cos(r), selected by n mod 4
├── cos_f32.asm / cos_f64.asm     ← same reduction as sin, cosine's
│                                    quadrant table
├── tan_f32.asm / tan_f64.asm     ← sin(x)/cos(x), composed from the two
│                                    above rather than its own reduction
└── hypot_f32.asm / hypot_f64.asm ← sqrt(x^2+y^2) via a = max(|x|,|y|),
                                     hypot = a*sqrt(1+(b/a)^2) — overflow/
                                     underflow-safe, composed from sqrt
```

---

## Design decisions, and why

**Saturate instead of overflowing to Inf/0 (exp only).**
`exp_f32`/`exp_f64` clamp their input to `[MINLOG, MAXLOG]` — the exact
bounds that keep the reconstructed exponent `k` inside the valid *normal*
float range — and return the largest/smallest finite value for input beyond
that, rather than true `±Inf`/`0`. This is a deliberate choice, not a
missing case: it avoids a branch on the hot path and a kernel math library
saturating gracefully is usually preferable to it producing a literal
infinity that then has to be checked for everywhere downstream. `pow`
inherits this for extreme-magnitude results (it composes `exp`), but treats
`x == 0` as a genuine pole and returns true `+Inf`, since that's a different
kind of "extreme" — a division-by-zero-shaped discontinuity, not a smooth
range limit.

**log and pow branch per-element; exp doesn't.**
`exp`'s only special-case handling is a branchless clamp, so its
array/inplace paths run the full algorithm packed (4-wide for f32, 2-wide
for f64). `log` and `pow` have genuine per-element domain decisions (zero,
negative, NaN, Inf, subnormal, integer-vs-fractional exponent) that aren't
worth encoding as branchless packed blends — their array/inplace paths call
the scalar routine per element instead. Slower per element, far less bug
surface for functions whose domain logic is the hard part.

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
enough that a float32-rounded copy of the pi/2 hi/lo split had already lost
the "n·hi stays exact" property the split exists for. This is the standard
fix real `sinf`/`cosf` implementations use, not an original technique. All
four trig files share the same practical accuracy bound as a result: exact
to a few ULP for `|x|` up to roughly `2^32 * pi/2 ≈ 6.7e9`, measurably
degraded beyond it (still not exempt from the same "not Payne-Hanek"
caveat `exp`'s clamping sidesteps by a different route).

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
NASM has no file-private symbol concept, and this whole tree eventually
becomes a single `%include` chain assembled as one translation unit (see
`boot/Makefile`). A generic name like `const_one_f32` declared in two
different files is a silent build-breaker the moment both get pulled in —
it doesn't fail until integration, long after the file that introduced it
looked finished. Every constant here is prefixed with its file's own name
(`sqrtf32_half`, `logf64_inv23`, ...) for exactly this reason.

---

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

Every function in this module has been numerically verified against a
reference implementation (Python's `math` module, IEEE double throughout)
via a `ld -shared` + `ctypes` harness — no C compiler needed, since the
kernel toolchain doesn't have one. This isn't optional polish: this
methodology is what caught every real bug listed below before it could ship.
Typical relative error: ~1e-7–1e-8 for f32, ~1e-14–1e-16 for f64, consistent
with the precision of the reduced-range series/polynomial used.

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

---

## Dependencies

```
math_fn/ depends on:
  → nothing at runtime (each file is self-contained except:
    pow_f32/f64 call log_f32/f64 and exp_f32/f64;
    tan_f32/f64 call sin_f32/f64 and cos_f32/f64;
    hypot_f32/f64 call sqrt_f32/f64 — all from this same directory)

math_fn/ is depended on by:
  → norm/, stats/, gemm/ (activation functions, softmax, normalization)
  → every module that needs a transcendental function
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# scalar — umath Scalar Numeric Operations

**Module:** `scalar/`
**Tier:** 0–1 (self-contained; no dependency on `bits/` despite operating
on the same bit patterns — see Design notes)
**Part of:** umath — unified math library

---

## Overview

`scalar` implements the numeric operations one level above raw bit
manipulation and one level below transcendental math: absolute value,
min/max, clamp, sign, negate, round/floor/ceil/trunc, reciprocal — for
`i32`/`i64`/`f32`/`f64`. Every file follows the same shape: a scalar
version, an `_array` version (unrolled SIMD, 4x or more), an `_inplace`
version, and usually a handful of related utilities (NaN/Inf checks,
counting, copysign) that belong with the same operation rather than off in
a separate predicates module.

---

## Files

```
scalar/
├── abs_f32.asm / abs_f64.asm / abs_i32.asm / abs_i64.asm
├── ceil_f32.asm / ceil_f64.asm
├── floor_f32.asm / floor_f64.asm
├── round_f32.asm / round_f64.asm
├── trunc_f32.asm / trunc_f64.asm
├── clamp_f32.asm / clamp_f64.asm / clamp_i32.asm
├── max_f32.asm / max_f64.asm / max_i32.asm / max_i64.asm
├── min_f32.asm / min_f64.asm / min_i32.asm / min_i64.asm
├── neg_f32.asm / neg_f64.asm
├── sign_f32.asm / sign_f64.asm
├── fmod_f32.asm / fmod_f64.asm  ← fmod, remainder, remquo: exact, by
│                                  integer long division on the mantissas
├── frexp_f32.asm / frexp_f64.asm ← frexp, ilogb, logb, modf
├── nextafter_f32.asm / nextafter_f64.asm ← nextafter, nextup, nextdown
├── fdim_f32.asm / fdim_f64.asm  ← positive difference
└── reciprocal_f32.asm  ← exact (divss/divps) + fast approx (rcpss/rcpps)
                           + Newton-Raphson refined, each with array/
                           inplace variants (see math_fn/README.md's
                           "Design decisions" for the same approx/refined
                           pattern applied to sqrt)
```

`clamp_i64`, `neg_i32/i64`, `sign_i32/i64`, and a `reciprocal_f64` are not
yet present — not an oversight to route around, just not swept yet.

---

## Calling convention

System V AMD64 ABI:

```
f32/f64 scalar args → xmm0 (, xmm1 for two-operand ops like clamp/max/min)
i32/i64 scalar args → edi/rdi (, esi/rsi)
array args           → rdi = dst, rsi = src, rdx = count
inplace args         → rdi = buf, rsi = count
return               → xmm0 (float) or eax/rax (int/bool)
```

---

## Design notes

**No dependency on `bits/`, even though the bit-pattern tricks look similar.**
`abs_f64`'s sign-bit-clear mask and `bits/bit64.asm`'s `fp64_abs` do
essentially the same AND-mask operation, but `scalar/` keeps its own
`.rodata` constants rather than calling into `bits/`. A scalar float
operation and a bit-pattern-inspection primitive are different concerns
even when the underlying trick is one instruction — `scalar/` is where
"what should `abs(x)` return" lives, `bits/` is where "how do I read a
float's sign bit" lives, and the fact that the answer to the first is
implemented using the second is an implementation detail, not a reason to
couple the two modules together.

**`_array` isn't a loop over the scalar function.** Every array variant
in this module runs the operation packed (SSE `ps`/`pd`), unrolled to
process multiple SIMD-widths per iteration, with a vector-width tail and a
scalar residual tail — not a `call` per element. Contrast this with
`math_fn/log_f32_array`, which *does* call its scalar routine per element,
because `log`'s domain branching makes a packed reduction not worth the bug
surface. The functions in `scalar/` have no such per-element branching
(abs/min/max/clamp/round are all branchless at the bit or instruction
level), so there's no reason to give up the throughput.

**The IEEE 754 helpers are exact.**
`fmod`, `remainder` and `remquo` never round:
- Both operands become integer mantissas.
- The remainder is a long division on those integers, at most 63 bits
  per `div`, so even the widest exponent gap takes 34 steps.
- The quotient's low bits are carried along: `remainder` rounds the
  quotient half to even with them, and `remquo` reports them.
- The f32 versions widen to double, where the same exact result is
  itself a float.

`frexp`, `ilogb`, `logb` and `modf` read the exponent from the bits
(subnormals normalized, down to -1074 / -149). `nextafter`, `nextup` and
`nextdown` step the bit pattern by one. `tests/test_ieee.py` checks all
of them bit for bit against exact references. Their array variants (fmod,
remainder, fdim) call the scalar per element through
`math_fn/loops.asm`, unlike the packed arrays above.

**Approx/refined tiers exist where a hardware estimate instruction exists.**
`reciprocal_f32` has exact (`divps`)/approx (`rcpps`)/refined
(`rcpps` + one Newton-Raphson step) variants because x86 actually offers a
fast reciprocal *estimate* instruction to refine. Most of this module
(abs, min, max, clamp, round) has no such estimate/refine split because the
exact operation is already a single instruction — there's nothing to trade
precision for speed on.

---

## Dependencies

```
scalar/ depends on:
  → nothing for the original operations (Tier 0, self-contained; see
    Design notes above)
  → math_fn/scalbn_f64.asm and math_fn/loops.asm for fmod/remainder
    (exact rescaling of the remainder, shared array loops)

scalar/ is depended on by:
  → math_fn/  (range clamps, sign handling)
  → norm/, stats/, gemm/  (elementwise scalar ops on tensor data)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

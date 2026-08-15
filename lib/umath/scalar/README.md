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
  → nothing (Tier 0, self-contained; see Design notes above)

scalar/ is depended on by:
  → math_fn/  (range clamps, sign handling)
  → norm/, stats/, gemm/  (elementwise scalar ops on tensor data)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

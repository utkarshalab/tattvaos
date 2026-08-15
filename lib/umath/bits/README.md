# bits — umath Bit Manipulation Primitives

**Module:** `bits/`
**Tier:** 0 (no dependencies within umath)
**Part of:** umath — unified math library

---

## Overview

`bits` is the lowest-level module in umath: fixed-width integer and
IEEE-754 bit-pattern manipulation, with no floating-point *arithmetic*
happening anywhere in it (that's `scalar/` and `math_fn/`). Every other
module that needs to inspect or construct a bit pattern — extracting an
exponent field, building a sign mask, testing alignment, counting set bits
— goes through here rather than reimplementing it inline. `math_fn/`'s
`log`/`exp`/`pow` in particular lean directly on the per-width float
decompose/compose helpers (`fp32_exponent`, `fp64_mantissa`, etc.) for
their range-reduction bit tricks.

---

## Files

```
bits/
├── bit1.asm .. bit512.asm  ← one file per fixed width (1,2,4,8,16,32,64,
│                              128,512 bits): saturating add/sub, min/max,
│                              rotate, sign/zero extend, popcount, plus
│                              width-specific float bit-pattern helpers
│                              (fp16/bf16/tf32/fp32/fp64/fp128, complex
│                              compose/real/imag for cf32/cf64)
├── align_up.asm / align_down.asm  ← round a value/pointer up or down to
│                                     an alignment boundary, plus
│                                     is_aligned checks
├── bitextract.asm / bitinsert.asm ← extract/insert an arbitrary bit range
│                                     from a scalar or buffer (PEXT/PDEP-
│                                     backed where available)
├── bitmask.asm             ← construct masks: single-bit, range, low/high
│                              N bits, isolate/clear LSB
├── bitreverse.asm          ← reverse bit order (8/16/32/64-bit)
├── bitrot_l.asm / bitrot_r.asm ← rotate left/right, scalar and buffer/
│                                  array forms
├── clz.asm / ctz.asm       ← count leading/trailing zeros (8 through
│                              64-bit, with a soft fallback alongside the
│                              BSR/BSF-backed fast path)
├── nibble.asm              ← 4-bit-granular get/set/extract/popcount/
│                              interleave over a buffer
├── parity.asm              ← bit parity (single word, buffer, masked,
│                              row-xor)
├── popcount.asm            ← population count (8 through 64-bit, buffer
│                              form, plus a soft fallback for CPUs without
│                              POPCNT)
└── round_pow2.asm          ← round up/down to the nearest power of two,
                                is_pow2, log2_floor/ceil
```

---

## Calling convention

System V AMD64 ABI:

```
scalar int args → edi/rdi, esi/rsi, edx/rdx, ...
buffer args      → rdi = ptr, rsi = count (or rdi = dst, rsi = src, rdx = count)
bool return       → eax, 0 or 1
```

Per-width float helpers (`fp32_exponent`, `bf16_is_nan`, etc.) take the raw
bit pattern in a GPR, not a float in an xmm register — callers that have an
actual float value use `movd`/`movq` to get its bits into a GPR first. This
keeps `bits/` entirely free of floating-point instructions; it manipulates
representations, `scalar/`/`math_fn/` do arithmetic on them.

---

## Design notes

**One file per width, not one file per operation.**
`bit32.asm` holds add_sat/sub_sat/min/max/cmp/rotate/bswap/sign-extend *for
32-bit values*, rather than a `saturating_add.asm` covering every width.
Operations on a given width share bit-tricks and constants (saturation
bounds, sign masks) that don't transfer cleanly to other widths, so keeping
a width together in one file reads more like a coherent unit than splitting
by operation would.

**Float bit-pattern helpers live beside their integer width, not in a
separate float-bits file.** `bit16.asm` has both plain 16-bit integer ops
and `fp16_*`/`bf16_*` helpers, because both are "the 16-bit-wide
operations" — the split that matters is by width, not by int-vs-float,
since a float bit-pattern helper (`fp32_exponent`) is exactly as much an
integer operation on the underlying bits as `bit32_rotl` is.

**Software fallbacks sit next to the hardware-instruction path.**
`popcount32` (POPCNT) has `popcount32_soft` beside it; `clz32`/`ctz32`
(LZCNT/TZCNT or BSR/BSF) likewise. Anything that dispatches on CPU features
(`cpuid/`, once implemented) picks between them at runtime rather than this
module assuming a baseline.

---

## Dependencies

```
bits/ depends on:
  → nothing (Tier 0, self-contained)

bits/ is depended on by:
  → dtype/          (bit-pattern classification is bit-aware)
  → memory/          (alignment checks)
  → scalar/, math_fn/  (float bit-pattern decompose/compose)
  → hash/, compress/, convert/  (planned — bit-level codecs)
  → every module that needs raw bit manipulation
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# convert — umath dtype Conversion

**Module:** `convert/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

The actual cast execution between dtypes: `dtype/dtype_cast.asm` describes
which conversions are lossless/safe/unsafe/require-quantization (the
235×235 policy table), `convert/` is where the conversion *code* for each
of those pairs lives — the bit-shuffling, rounding, and range-clamping that
turns an `FP32` bit pattern into a `BF16` one, or an `INT8` into a `Q4_0`
nibble.

## Planned scope

- Float-width conversions: `f64_to_f32`, `f32_to_f16`, `f32_to_bf16`, and
  back, each following the rounding/truncation rule `dtype_cast.asm`
  assigns that pair
- Int-width conversions with explicit overflow behavior (saturate vs. wrap,
  matching what `dtype_cast.asm`'s safety level says)
- Int↔float conversions
- Entry points for the sub-byte and quantized dtypes, calling into
  `compress/` for the quantization math itself

## Dependencies (anticipated)

```
convert/ depends on:
  → dtype/  (dtype_cast's safety-level table drives which path runs)
  → bits/   (bit-pattern manipulation for each format)
  → math_fn/, scalar/  (rounding for lossy narrowing conversions)

convert/ is depended on by:
  → compress/  (quantization needs a cast as its last step)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

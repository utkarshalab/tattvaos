# compress — umath Numeric Array Compression

**Module:** `compress/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Lightweight, numeric-array-shaped compression: delta encoding, run-length
encoding, and the block-scale quantization schemes `dtype/`'s promotion
table already lists as cast-safety "Level 4" targets (`Q4_0`, `MXFP4`,
etc.) — computing the actual scale/zero-point and packing the values, not
just describing the format the way `dtype/` does. General-purpose byte
compression (DEFLATE/LZ4/zstd-shaped) belongs to `lib/ucmp/` at the
top-level `lib/` category, not here; this module is specifically about
numeric-array-aware compression where knowing the data is a tensor of a
known dtype is what makes the scheme effective.

## Planned scope

- Delta / delta-of-delta encoding for monotonic or slowly-varying arrays
- RLE for sparse/repetitive numeric data
- Block quantization: compute per-block scale (and zero-point for
  asymmetric schemes), pack to `Q4_0`/`Q8_0`/`MXFP4`-shaped output,
  matching the dtypes `dtype/dtype_id.asm` already reserves IDs for
- Corresponding decompress/dequantize paths

## Dependencies (anticipated)

```
compress/ depends on:
  → dtype/    (target dtype's range/precision for quantization)
  → convert/  (the actual cast/pack step)
  → bits/     (sub-byte packing for Q4-shaped formats)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

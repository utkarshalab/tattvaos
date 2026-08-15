# format — umath Number Formatting

**Module:** `format/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Number-to-string and string-to-number conversion: printf-style float
formatting (fixed, scientific, shortest-round-trip), integer formatting in
arbitrary bases, and parsing floats/ints back out of a byte buffer. This is
numeric formatting specifically — `dtype/dtype_name.asm` already handles
*dtype* names ("fp16", "mxfp8_e4m3"), which is a different, much smaller
problem than formatting an arbitrary `f64` value.

## Planned scope

- `format_f32`/`format_f64` — fixed and scientific notation, configurable
  precision
- `format_i32`/`format_i64`/`format_u32`/`format_u64` — arbitrary base
  (2/8/10/16), signed/unsigned
- `parse_f32`/`parse_f64`/`parse_i64` — the inverse direction
- A shortest-round-trip float formatter (Grisu/Ryu-shaped) is a plausible
  eventual addition here but is a substantially harder problem than the
  fixed/scientific paths above — likely comes later, not in the first pass

## Dependencies (anticipated)

```
format/ depends on:
  → math_fn/  (log10/pow for digit-count and scientific-notation exponent)
  → dtype/    (type-generic entry point dispatching to the right formatter)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

# histogram — umath Array Binning

**Module:** `histogram/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Binning numeric arrays into a histogram: fixed-width bins over a
known or scanned min/max range, counting, and the min/max scan pass itself.
Used both as a diagnostic tool (distribution of values in a tensor, useful
when picking a quantization scale for `compress/`) and as a building block
for `stats/`'s percentile/median computation, which is far cheaper via a
histogram-based approximation than an exact sort for large arrays.

## Planned scope

- `histogram_minmax_scan` — single pass to find an array's range
- `histogram_build` — fixed bin-width histogram given a range and bin count
- `histogram_percentile` — approximate percentile from bin counts (feeds
  `stats/`)
- Streaming/incremental variants for arrays too large to hold in one pass

## Dependencies (anticipated)

```
histogram/ depends on:
  → scalar/  (min/max scan)
  → dtype/   (bin boundaries need dtype range info)

histogram/ is depended on by:
  → stats/     (approximate percentiles)
  → compress/  (picking a quantization scale from the observed distribution)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

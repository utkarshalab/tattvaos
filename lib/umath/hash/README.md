# hash — umath Array Hashing

**Module:** `hash/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Non-cryptographic hash functions over numeric buffers — for tensor
caching/memoization, dedup, and hash-based lookup structures elsewhere in
umath (a future `lut/` or `sort/`-adjacent hash table). Cryptographic
hashing belongs to `crypto/ucrypt/` at the repo's top level; this module's
hash functions exist purely for speed and distribution quality, not
collision resistance against an adversary.

## Planned scope

- A general-purpose fast hash (FNV-1a or a Murmur/xxHash/wyhash-shaped
  mix — algorithm choice deferred to when this folder is actually swept)
  over arbitrary byte buffers
- A dtype-aware array hash (hashes float `NaN`/`±0` consistently regardless
  of bit pattern, so semantically-equal tensors hash equal)
- Incremental/streaming hash state, for hashing large arrays in blocks

## Dependencies (anticipated)

```
hash/ depends on:
  → dtype/  (NaN/±0-normalized hashing needs dtype traits)
  → bits/   (rotate/mix primitives)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

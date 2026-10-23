# uttf — Utkarsha Tensor Transfer Format

**Module:** `lib/ai/formats/uttf/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** lib/ai — Artificial Intelligence Category

---

## Purpose

Utkarsha OS native model format. Content-addressed, dtype-typed, snapshot-compatible
with UFS. Designed for zero-copy loading directly from disk into inference
registers — no Python, no framework, no runtime.

## Planned scope

- `read.asm` — Parse UTTF header, content-addressed object index, tensor table
- `mmap.asm` — Memory-map tensors from UFS snapshots into pinned pages
- `validate.asm` — UTHF magic, version, dtype IDs, and BLAKE3 content hash
- `convert.asm` — Convert GGUF / safetensors → UTTF

## Dependencies

```text
uttf/ depends on:
  → mem/      (memory allocation, arenas, pinmem)
  → io/       (file primitives, UFS mmap)
  → dtype/    (213-type classification system)
  → uhash/    (content addressing via BLAKE3 / SHA-256)
  → ufile/    (magic bytes / MIME detection)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

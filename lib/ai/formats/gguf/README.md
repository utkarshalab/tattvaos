# gguf — GGUF Model Format Reader

**Module:** `lib/ai/formats/gguf/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** lib/ai — Artificial Intelligence Category

---

## Purpose

Read GGUF (llama.cpp standard) model files. The most common open-weight
model format. Memory-mapped loading with zero copies where possible.

## Planned scope

- `read.asm` — Parse GGUF header, metadata KV pairs, and tensor info table
- `mmap.asm` — Memory-map tensor weights directly from file into address space
- `validate.asm` — Magic number, version, and tensor count validation

## Dependencies

```text
gguf/ depends on:
  → mem/    (memory allocation)
  → io/     (file primitives)
  → dtype/  (type classification for GGUF quantization types)
  → ufile/  (magic bytes / MIME detection)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

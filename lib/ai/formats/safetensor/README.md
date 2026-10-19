# safetensor — SafeTensors Model Format Reader

**Module:** `lib/ai/formats/safetensor/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** lib/ai — Artificial Intelligence Category

---

## Purpose

Read safetensors (HuggingFace standard) model files. Safe deserialization,
memory-mapped loading, no arbitrary code execution.

## Planned scope

- `read.asm` — Parse safetensors header, metadata JSON, and tensor offsets
- `mmap.asm` — Memory-map tensor weights directly from file
- `validate.asm` — Header magic, header size, and offset table validation

## Dependencies

```text
safetensor/ depends on:
  → mem/    (memory allocation)
  → io/     (file primitives)
  → dtype/  (type classification for safetensor dtypes)
  → ufile/  (magic bytes / MIME detection)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

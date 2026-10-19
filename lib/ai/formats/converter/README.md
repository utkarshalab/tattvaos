# converter — Model Format Converter

**Module:** `lib/ai/formats/converter/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** lib/ai — Artificial Intelligence Category

---

## Purpose

Convert model weights between GGUF, safetensors, and UTTF. One tool, all
supported conversions. Runs at build time or on-device as needed.

## Planned scope

- `convert.asm` — Main converter entry point
- `to_ut tf.asm` — GGUF / safetensors → UTTF
- `to_gguf.asm` — UTTF / safetensors → GGUF
- `to_safetensor.asm` — GGUF / UTTF → safetensors

## Dependencies

```text
converter/ depends on:
  → gguf/     (GGUF reader)
  → safetensor/  (safetensors reader)
  → uttf/     (UTTF writer)
  → mem/      (memory allocation for conversion buffers)
  → io/       (file read/write)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

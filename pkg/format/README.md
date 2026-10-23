# pkg/format — Package Format

**Module:** `pkg/format/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `pkg/` — Package System

---

## Purpose

`.upk` package format specification — package format spec, manifest, and
signature handling for Utkarsha OS packages.

## Files

```
pkg/format/
├── upk.asm      ← .upk package format spec
├── manifest.asm ← package manifest
└── sign.asm     ← package signature
```

## Planned scope

- `.upk` package format specification
- Package manifest handling
- Package signature verification

## Dependencies

```text
pkg/format/ depends on:
  → crypto/usign/   (digital signatures)
  → lib/ufile/      (file operations)
  → lib/uhash/      (hashing for integrity)
```

---

*pkg/format — Package Format*
*pure x86-64 assembly, no dependencies, no OS*

# platform/x86_64 — x86-64 Platform Support

**Module:** `platform/x86_64/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `platform/` — Architecture-Specific Code

---

## Purpose

x86-64 specific platform initialization, CPU feature detection, and hardware
abstraction for Utkarsha OS.

## Files

```
platform/x86_64/
├── platform.asm   ← platform init and halt
└── README.md      ← this file
```

## Dependencies

```text
platform/x86_64/ depends on:
  → kernel/  (kernel interfaces)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

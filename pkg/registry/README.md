# pkg/registry — Package Registry

**Module:** `pkg/registry/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `pkg/` — Package System

---

## Purpose

Package registry for Tattva OS — tracks installed packages, versions, and
install paths.

## Files

```
pkg/registry/
├── registry.asm   ← package registry implementation
└── README.md      ← this file
```

## Planned scope

- Package registry database
- Install/remove tracking
- Dependency tracking

## Dependencies

```text
pkg/registry/ depends on:
  → storage/uxfs/   (filesystem storage)
  → lib/io/         (file I/O)
```

---

*pkg/registry — Package Registry*
*pure x86-64 assembly, no dependencies, no OS*

# dist/urpc — RPC Framework

**Module:** `dist/urpc/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `dist/` — Distributed Computing Layer

---

## Purpose

RPC (Remote Procedure Call) framework for Utkarsha OS — BXP-based async calls
between nodes, zero-copy where possible.

## Files

```
dist/urpc/
├── rpc.asm      ← RPC framework entry point
└── README.md    ← this file
```

## Planned scope

- Async RPC calls between nodes
- BXP-based transport
- Zero-copy where possible

## Dependencies

```text
dist/urpc/ depends on:
  → dist/udist/   (distributed runtime)
  → storage/ubxp/ (BXP binary protocol)
  → unet/         (network transport)
```

---

*dist/urpc — RPC Framework*
*pure x86-64 assembly, no dependencies, no OS*

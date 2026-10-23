# dist/uraft — Raft Consensus

**Module:** `dist/uraft/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `dist/` — Distributed Computing Layer

---

## Purpose

Raft consensus algorithm implementation for Utkarsha OS — leader election,
log replication, and consistency for distributed state.

## Files

```
dist/uraft/
├── raft.asm      ← Raft consensus implementation
└── README.md     ← this file
```

## Planned scope

- Leader election
- Log replication
- Consistency and safety guarantees

## Dependencies

```text
dist/uraft/ depends on:
  → dist/udist/   (distributed runtime)
  → unet/         (network transport)
```

---

*dist/uraft — Raft Consensus*
*pure x86-64 assembly, no dependencies, no OS*

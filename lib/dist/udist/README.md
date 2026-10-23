# dist/udist — Distributed Runtime

**Module:** `dist/udist/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `dist/` — Distributed Computing Layer

---

## Purpose

Distributed runtime for Tattva OS — node identity, membership protocol,
heartbeat, and failure detection for multi-node clusters.

## Files

```
dist/udist/
├── dist.asm      ← distributed runtime entry point
└── README.md     ← this file
```

## Planned scope

- Node identity and membership
- Heartbeat and failure detection
- Cluster topology management

## Dependencies

```text
dist/udist/ depends on:
  → unet/    (network transport)
  → lib/umath/  (math primitives)
  → lib/io/     (I/O primitives)
```

---

*dist/udist — Distributed Runtime*
*pure x86-64 assembly, no dependencies, no OS*

# tests/unit — Unit Tests

**Module:** `tests/unit/`
**Status:** Skeletoned — directory structure created, implementation pending.
**Part of:** `tests/` — Global Test Suite

---

## Purpose

Unit tests for individual Utkarsha OS modules — kernel subsystems, libraries,
and applications. Each test module tests a single component in isolation.

## Files

```
tests/unit/
├── test_suite.asm   ← test runner entry point
└── README.md        ← this file
```

## Planned scope

- `test_mem.asm` — memory allocator tests
- `test_str.asm` — string library tests
- `test_sched.asm` — scheduler tests
- `test_crypto.asm` — crypto library tests
- `test_ai.asm` — AI inference stack tests

---

*tests/unit — Unit Tests*
*pure x86-64 assembly, no dependencies, no OS*

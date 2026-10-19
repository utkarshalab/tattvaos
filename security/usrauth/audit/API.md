# audit — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention:
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls.
- Return convention: `rax = 0` on success, nonzero errno-style on failure.

## Symbol Index

### audit (audit_decision_log)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `audit_init` | none | rax = status | Initialize audit decision log |
| `audit_shutdown` | none | rax = status | Shut down audit decision log |
| `audit_status` | none | rax = status | Current subsystem status |
| `audit_version` | none | rax = ptr | NUL-terminated version string |

## Build

```bash
make -C security/usrauth/audit all
make -C security/usrauth/audit test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

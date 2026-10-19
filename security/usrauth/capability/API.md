# capability — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention.

## Symbol Index

### cap (capability)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `cap_init` | none | rax = status | Initialize capability subsystem |
| `cap_shutdown` | none | rax = status | Shut down capability subsystem |
| `cap_status` | none | rax = status | Current subsystem status |
| `cap_version` | none | rax = ptr | NUL-terminated version string |
| `cap_issue` | none | rax = result | Issue a capability token |
| `cap_evaluate` | rdi = context | rax = verdict | Evaluate capability caveats |
| `cap_revoke` | rdi = token | rax = result | Revoke a capability |

### restrict (capability restrictions)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `restrict_init` | none | rax = status | Initialize restrictions |
| `restrict_shutdown` | none | rax = status | Shut down restrictions |
| `restrict_status` | none | rax = status | Current status |
| `restrict_version` | none | rax = ptr | Version string |
| `restrict_evaluate` | rdi = context | rax = verdict | Evaluate caveats |

## Build

```bash
make -C security/usrauth/capability all
make -C security/usrauth/capability test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

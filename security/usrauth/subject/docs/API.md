# subject — API Reference

## Overview
Enterprise-grade security module for Tattva OS. All symbols follow the
NASM x86-64 calling convention.

## Conventions
- All functions preserve callee-saved registers (rbx, rbp, r12–r15).
- Return convention: rax = 0 on success, nonzero errno-style on failure.
- All pointers are 64-bit virtual addresses.

## Symbols

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `<name>_init` | none | rax = status | Initialize the subsystem |
| `<name>_shutdown` | none | rax = status | Shut down and release resources |
| `<name>_status` | none | rax = status | Return current subsystem status |
| `<name>_version` | none | rax = ptr | Return NUL-terminated version string |

## Error Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General failure |
| 2 | Not initialized |
| 3 | Invalid argument |
| 4 | Resource exhausted |
| 5 | Access denied |

## Build

```bash
make -C security/usrauth/subject
make -C security/usrauth/subject test
```

## License
Apache-2.0

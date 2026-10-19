# identity — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention.

## Symbol Index

### password

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `password_init` | none | rax = status | Initialize password provider |
| `password_shutdown` | none | rax = status | Shut down password provider |
| `password_status` | none | rax = status | Current status |
| `password_version` | none | rax = ptr | NUL-terminated version string |
| `password_authenticate` | rdi = credentials | rax = result | Authenticate with password |

### webauthn

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `webauthn_init` | none | rax = status | Initialize WebAuthn provider |
| `webauthn_shutdown` | none | rax = status | Shut down WebAuthn |
| `webauthn_status` | none | rax = status | Current status |
| `webauthn_version` | none | rax = ptr | Version string |

### svid

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `svid_init` | none | rax = status | Initialize SVID provider |
| `waf_svid_shutdown` | none | rax = status | Shut down SVID |
| `waf_svid_status` | none | rax = status | Current status |
| `waf_svid_version` | none | rax = ptr | Version string |

### attest

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_attest_init` | none | rax = status | Initialize attestation |
| `waf_attest_shutdown` | none | rax = status | Shut down attestation |
| `waf_attest_status` | none | rax = status | Current status |
| `waf_attest_version` | none | rax = ptr | Version string |

## Build

```bash
make -C security/usrauth/identity all
make -C security/usrauth/identity test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

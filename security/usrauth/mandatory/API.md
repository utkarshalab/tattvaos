# mandatory — API Reference

## Symbol Index

### integrity

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_integrity_init` | none | rax = status | Initialize integrity MAC |
| `waf_integrity_shutdown` | none | rax = status | Shut down integrity |
| `waf_integrity_status` | none | rax = status | Current status |
| `waf_integrity_version` | none | rax = ptr | Version string |
| `waf_integrity_check` | rdi = ctx | rax = verdict | Integrity check |

### mls

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_mls_init` | none | rax = status | Initialize MLS |
| `waf_mls_shutdown` | none | rax = status | Shut down MLS |
| `waf_mls_status` | none | rax = status | Current status |
| `waf_mls_version` | none | rax = ptr | Version string |
| `waf_mls_check` | rdi = ctx | rax = verdict | MLS access check |

### te

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_te_init` | none | rax = status | Initialize Type Enforcement |
| `waf_te_shutdown` | none | rax = status | Shut down TE |
| `waf_te_status` | none | rax = status | Current status |
| `waf_te_version` | none | rax = ptr | Version string |
| `waf_te_check` | rdi = ctx | rax = verdict | TE access check |

## Build

```bash
make -C security/usrauth/mandatory all
make -C security/usrauth/mandatory test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

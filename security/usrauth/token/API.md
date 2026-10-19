# token — API Reference

## Symbol Index

### token

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_token_init` | none | rax = status | Initialize token subsystem |
| `waf_token_shutdown` | none | rax = status | Shut down token |
| `waf_token_status` | none | rax = status | Current status |
| `waf_token_version` | none | rax = ptr | Version string |
| `waf_token_issue` | rdi = credentials | rax = token_id | Issue token |
| `waf_token_validate` | rdi = token | rax = verdict | Validate token |

### caveat

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_caveat_init` | none | rax = status | Initialize caveats |
| `waf_caveat_shutdown` | none | rax = status | Shut down caveats |
| `waf_caveat_status` | none | rax = status | Current status |
| `waf_caveat_version` | none | rax = ptr | Version string |
| `waf_caveat_evaluate` | rdi = context | rax = verdict | Evaluate caveats |

### revoke

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_revoke_init` | none | rax = status | Initialize revocation |
| `waf_revoke_shutdown` | none | rax = status | Shut down revocation |
| `waf_revoke_status` | none | rax = status | Current status |
| `waf_revoke_version` | none | rax = ptr | Version string |
| `waf_revoke_check` | rdi = token | rax = verdict | Check revocation |

## Build

```bash
make -C security/usrauth/token all
make -C security/usrauth/token test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

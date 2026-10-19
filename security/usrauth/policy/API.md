# policy — API Reference

## Symbol Index

### policy

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_policy_init` | none | rax = status | Initialize policy engine |
| `waf_policy_shutdown` | none | rax = status | Shut down policy |
| `waf_policy_status` | none | rax = status | Current status |
| `waf_policy_version` | none | rax = ptr | Version string |
| `waf_policy_load` | rdi = rules | rax = result | Load policy rules |
| `waf_policy_evaluate` | rdi = ctx | rax = verdict | Evaluate policy |

### attribute

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_attribute_init` | none | rax = status | Initialize attribute policy |
| `waf_attribute_shutdown` | none | rax = status | Shut down attribute |
| `waf_attribute_status` | none | rax = status | Current status |
| `waf_attribute_version` | none | rax = ptr | Version string |
| `waf_attribute_evaluate` | rdi = ctx | rax = verdict | Evaluate ABAC attributes |

### consent

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_consent_init` | none | rax = status | Initialize consent |
| `waf_consent_shutdown` | none | rax = status | Shut down consent |
| `waf_consent_status` | none | rax = status | Current status |
| `waf_consent_version` | none | rax = ptr | Version string |

### relation

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_relation_init` | none | rax = status | Initialize relation |
| `waf_relation_shutdown` | none | rax = status | Shut down relation |
| `waf_relation_status` | none | rax = status | Current status |
| `waf_relation_version` | none | rax = ptr | Version string |
| `waf_relation_check` | rdi = ctx | rax = verdict | Check relation |

### ttl

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_ttl_init` | none | rax = status | Initialize TTL |
| `waf_ttl_shutdown` | none | rax = status | Shut down TTL |
| `waf_ttl_status` | none | rax = status | Current status |
| `waf_ttl_version` | none | rax = ptr | Version string |
| `waf_ttl_check` | rdi = ctx | rax = verdict | Check TTL |

## Build

```bash
make -C security/usrauth/policy all
make -C security/usrauth/policy test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

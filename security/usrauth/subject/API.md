# subject — API Reference

## Symbol Index

### subject

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_subject_init` | none | rax = status | Initialize subject table |
| `waf_subject_shutdown` | none | rax = status | Shut down subject table |
| `waf_subject_status` | none | rax = status | Current status |
| `waf_subject_version` | none | rax = ptr | Version string |
| `waf_subject_create` | rdi = credentials | rax = subject_id | Create subject |
| `waf_subject_lookup` | rdi = handle | rax = subject_record | Look up subject |

### table

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_table_init` | none | rax = status | Initialize subject table |
| `waf_table_shutdown` | none | rax = status | Shut down table |
| `waf_table_status` | none | rax = status | Current status |
| `waf_table_version` | none | rax = ptr | Version string |

### transition

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_transition_init` | none | rax = status | Initialize transitions |
| `waf_transition_shutdown` | none | rax = status | Shut down transitions |
| `waf_transition_status` | none | rax = status | Current status |
| `waf_transition_version` | none | rax = ptr | Version string |
| `waf_transition_apply` | rdi = ctx | rax = verdict | Apply transition |

### registry

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `waf_registry_init` | none | rax = status | Initialize registry |
| `waf_registry_shutdown` | none | rax = status | Shut down registry |
| `waf_registry_status` | none | rax = status | Current status |
| `waf_registry_version` | none | rax = ptr | Version string |
| `waf_registry_lookup_by_uid` | rdi = subject_id | rax = subject | Look up subject |

## Build

```bash
make -C security/usrauth/subject all
make -C security/usrauth/subject test
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

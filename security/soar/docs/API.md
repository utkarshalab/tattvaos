# soar — API Reference

> Enterprise-grade Security Orchestration, Automation & Response API reference.

## Overview

All symbols follow the NASM x86-64 calling convention:
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls.
- Return convention: `rax = 0` on success, nonzero errno-style on failure.
- All symbols follow the `soar_*` naming convention.

## Symbol Index

### soar (Main Dispatcher)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_init` | none | rax = status | Initialize SOAR engine |
| `soar_shutdown` | none | rax = status | Shut down SOAR engine |
| `soar_status` | none | rax = status | Current subsystem status |
| `soar_version` | none | rax = ptr | NUL-terminated version string |
| `soar_execute` | rdi = event_ctx | rax = verdict, rbx = reason, rcx = rule_id | Main enforcement entry point |
| `soar_get_stats` | rdi = stats buffer | rax = status | Return statistics snapshot |

### core_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_core_init` | none | rax = status | Initialize core engine |
| `soar_core_shutdown` | none | rax = status | Shut down core engine |
| `soar_core_status` | none | rax = status | Current component status |
| `soar_core_version` | none | rax = ptr | NUL-terminated version string |

### playbook_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_policy_init` | none | rax = status | Initialize playbook engine |
| `soar_policy_shutdown` | none | rax = status | Shut down playbook engine |
| `soar_policy_status` | none | rax = status | Current component status |
| `soar_policy_version` | none | rax = ptr | NUL-terminated version string |
| `soar_policy_load` | rdi = rules | rax = status | Load playbook rules |
| `soar_policy_evaluate` | rdi = ctx | rax = verdict | Evaluate playbook rules |

### alert_ingestor

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_alert_init` | none | rax = status | Initialize alert ingestor |
| `soar_alert_shutdown` | none | rax = status | Shut down alert ingestor |
| `soar_alert_status` | none | rax = status | Current component status |
| `soar_alert_version` | none | rax = ptr | NUL-terminated version string |
| `soar_alert_ingest` | rdi = alert | rax = status | Ingest an external alert |

### action_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_action_init` | none | rax = status | Initialize action engine |
| `soar_action_shutdown` | none | rax = status | Shut down action engine |
| `soar_action_status` | none | rax = status | Current component status |
| `soar_action_version` | none | rax = ptr | NUL-terminated version string |
| `soar_action_execute` | rdi = action | rax = status | Execute response action |

### case_manager

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_case_manager_init` | none | rax = status | Initialize case manager |
| `soar_case_manager_shutdown` | none | rax = status | Shut down case manager |
| `soar_case_manager_status` | none | rax = status | Current component status |
| `soar_case_manager_version` | none | rax = ptr | NUL-terminated version string |
| `soar_case_create` | rdi = case_data | rax = case_id | Create incident case |

### automation_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_automation_engine_init` | none | rax = status | Initialize automation engine |
| `soar_automation_engine_shutdown` | none | rax = status | Shut down automation engine |
| `soar_automation_engine_status` | none | rax = status | Current component status |
| `soar_automation_engine_version` | none | rax = ptr | NUL-terminated version string |
| `soar_automation_engine_execute` | rdi = workflow | rax = status | Execute automation workflow |

### integration_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_integration_engine_init` | none | rax = status | Initialize integration engine |
| `soar_integration_engine_shutdown` | none | rax = status | Shut down integration engine |
| `soar_integration_engine_status` | none | rax = status | Current component status |
| `soar_integration_engine_version` | none | rax = ptr | NUL-terminated version string |
| `soar_integration_engine_send` | rdi = data | rax = status | Send to external integration |

### scheduler

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_scheduler_init` | none | rax = status | Initialize scheduler |
| `soar_scheduler_shutdown` | none | rax = status | Shut down scheduler |
| `soar_scheduler_status` | none | rax = status | Current component status |
| `soar_scheduler_version` | none | rax = ptr | NUL-terminated version string |
| `soar_scheduler_add` | rdi = schedule | rax = status | Add scheduled playbook |

### metrics_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_metrics_engine_init` | none | rax = status | Initialize metrics engine |
| `soar_metrics_engine_shutdown` | none | rax = status | Shut down metrics engine |
| `soar_metrics_engine_status` | none | rax = status | Current component status |
| `soar_metrics_engine_version` | none | rax = ptr | NUL-terminated version string |
| `soar_metrics_engine_record` | rdi = metric | rax = status | Record SOAR metric |

### playbook_compiler

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_rulec_init` | none | rax = status | Initialize rule compiler |
| `soar_rulec_shutdown` | none | rax = status | Shut down rule compiler |
| `soar_rulec_status` | none | rax = status | Current component status |
| `soar_rulec_version` | none | rax = ptr | NUL-terminated version string |
| `soar_rulec_compile` | rdi = rule | rax = status | Compile playbook rule |

## Build

```bash
make -C security/soar all
make -C security/soar test
```

---\n\n## License\n\nApache-2.0 — see `LICENSE` at the repository root.\n
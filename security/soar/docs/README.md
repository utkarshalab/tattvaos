# security/soar — Security Orchestration, Automation & Response (SOAR)

## Purpose
Orchestrate security tools, automate response playbooks, and coordinate
incident response across Utkarsha OS security modules.

## Architecture
- **Orchestrator** — triggers actions across modules (usrauth, ips, malwarescan)
- **Playbooks** — encoded response procedures (YAML/JSON) per scenario
- **Actions** — atomic operations: revoke session, block IP, isolate host, etc.
- **Triggers** — event-driven: alerts from ids/ips/malwarescan/vuln_scan

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `soar_init` | none | rax = 0 | Initialize SOAR |
| `soar_shutdown` | none | rax = 0 | Shut down SOAR |
| `soar_status` | none | rax = status | Current status |
| `soar_load_playbook` | path | rax = result | Load a playbook |
| `soar_trigger` | playbook_id, event | rax = result | Execute playbook on event |
| `soar_action` | action_id, params | rax = result | Run a single action |

## Design Decisions
- Playbooks are declarative so new scenarios can be added without recompiling.
- Every SOAR action is audited through `usrauth/audit`.
- Actions are idempotent where possible; destructive actions require confirmation.

## Threat Model
- Compromised playbook triggers malicious actions → mitigated by signed playbook manifests.
- SOAR itself becomes attack surface → mitigated by least privilege + sandboxing.

## Status
Skeleton. `soar.asm` exports `soar_init`, `soar_shutdown`, `soar_status` as no-op stubs.

## Tests
Run: `make -C security/soar test`

## License
Apache-2.0

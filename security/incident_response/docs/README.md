# security/incident_response — Incident Response (IR)

## Purpose
Coordinate incident triage, containment, eradication, and recovery for
Tattva OS security events. Provides playbooks, runbooks, and automation hooks.

## Architecture
- **Triage** — event intake, severity classification, priority assignment
- **Containment** — isolate affected hosts, revoke sessions, block indicators
- **Eradication** — remove threat actor presence, patch vulnerabilities
- **Recovery** — restore services, validate integrity, post-incident review
- **Playbooks** — YAML/JSON-encoded response procedures per incident type

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ir_init` | none | rax = 0 | Initialize IR subsystem |
| `ir_shutdown` | none | rax = 0 | Shut down IR |
| `ir_status` | none | rax = status | Current status |
| `ir_declare` | incident_type, severity | rax = incident_id | Declare a new incident |
| `ir_contain` | incident_id | rax = result | Execute containment actions |
| `ir_close` | incident_id, resolution | rax = result | Close an incident |

## Design Decisions
- Every declared incident receives a unique, monotonically increasing ID.
- Containment actions are idempotent and recorded to the audit log.
- Playbooks are data-driven so new incident types can be added without code changes.

## Threat Model
- Attacker interferes with IR playbooks → mitigated by signed playbook manifests.
- Insider delays containment → mitigated by automated containment triggers.

## Status
Skeleton. `incident_response.asm` exports `ir_init`, `ir_shutdown`, `ir_status` as no-op stubs.

## Tests
Run: `make -C security/incident_response test`

## License
Apache-2.0

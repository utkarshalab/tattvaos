# security/privacy_compliance — Data Loss Prevention & Privacy Compliance

## Purpose
Data Loss Prevention (DLP), privacy controls, and regulatory compliance
reporting (GDPR, CCPA, HIPAA-style) for Utkarsha OS.

## Architecture
- **Classifier** — data classification (public, internal, confidential, restricted)
- **DLP Engine** — content inspection, egress monitoring, exfiltration blocking
- **Consent** — user consent management, data subject requests (DSAR)
- **Reporter** — compliance reports, audit trails, breach notification

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `privacy_init` | none | rax = 0 | Initialize compliance subsystem |
| `privacy_shutdown` | none | rax = 0 | Shut down |
| `privacy_status` | none | rax = status | Current status |
| `privacy_classify` | data, len | rax = classification | Classify data sensitivity |
| `privacy_check_egress` | flow | rax = verdict | Check egress against DLP policy |
| `privacy_consent_record` | subject, purpose | rax = result | Record user consent |

## Design Decisions
- Classification is mandatory: all data is assigned a sensitivity label at ingress.
- DLP decisions are final and auditable — every block is logged with rationale.
- Consent records are append-only and cryptographically bound to the subject.

## Threat Model
- Insider exfiltration → mitigated by DLP egress monitoring and endpoint controls.
- Consent forgery → mitigated by signed consent records.

## Status
Skeleton. `privacy_compliance.asm` exports `privacy_init`, `privacy_shutdown`, `privacy_status` as no-op stubs.

## Tests
Run: `make -C security/privacy_compliance test`

## License
Apache-2.0

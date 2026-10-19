# security/usrauth/audit — Decision Logging (Audit)

## Purpose
Immutable, append-only audit trail for every authorization decision made by
the usrauth reference monitor. Provides non-repudiation and forensic traceability.

## Architecture
- **Recorder** — appends decision records to the audit log
- **Sealer** — cryptographically seals/log-chains entries for tamper evidence
- **Reader** — queries and exports audit records for SIEM / forensics

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `audit_init` | none | rax = 0 | Initialize audit log |
| `audit_shutdown` | none | rax = 0 | Shut down audit |
| `audit_status` | none | rax = status | Current status |
| `audit_log` | subject, action, resource, verdict | rax = result | Record an authorization decision |
| `audit_verify` | entry, signature | rax = result | Verify log entry integrity |

## Design Decisions
- Append-only: entries are never modified or deleted.
- Log-chaining: each entry includes the hash of the previous entry.
- Audit writes are synchronous (fsync-equivalent) before a decision is acknowledged.

## Status
Skeleton. `decision_log.asm` exports `audit_init`, `audit_shutdown`, `audit_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/audit test`

## License
Apache-2.0

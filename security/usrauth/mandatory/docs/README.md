# security/usrauth/mandatory — Mandatory Access Control (MAC)

## Purpose
Mandatory access control layers: integrity levels, Multi-Level Security (MLS),
and Type Enforcement (TE). These are non-discretionary — subjects cannot
override them.

## Architecture
- **Integrity** — Biba-style integrity levels (no write-up, no read-down)
- **MLS** — Bell-LaPadula confidentiality levels (no read-up, no write-down)
- **TE** — Type Enforcement: domain + type transition rules

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `mac_init` | none | rax = 0 | Initialize MAC subsystem |
| `mac_shutdown` | none | rax = 0 | Shut down |
| `mac_status` | none | rax = status | Current status |
| `mac_check` | subject, object, operation | rax = verdict | MAC access check |
| `mac_label_set` | object, label | rax = result | Set object security label |
| `mac_domain_transition` | from, to | rax = result | TE domain transition |

## Design Decisions
- MAC is non-bypassable: checked after discretionary (RBAC/ABAC) but before grant.
- All three MAC models are ANDed — a request must pass integrity, MLS, and TE.
- Labels are immutable after object creation (except via explicit relabel).

## Status
Skeleton. `integrity.asm` / `mls.asm` / `te.asm` export `mac_init`, `mac_shutdown`, `mac_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/mandatory test`

## License
Apache-2.0

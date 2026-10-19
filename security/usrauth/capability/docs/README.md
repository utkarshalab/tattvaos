# security/usrauth/capability — Capabilities & Restrictions

## Purpose
Capability-based access control: unforgeable tokens representing delegated
authority, with restrictions (caveats) that attenuate the privilege they convey.

## Architecture
- **Capability** — issued capability object (subject + action + resource + caveat)
- **Restrict** — caveat evaluation (time, IP, duration, use-count)
- **Issuer** — mints capabilities after authorization check

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `cap_init` | none | rax = 0 | Initialize capability system |
| `cap_shutdown` | none | rax = 0 | Shut down |
| `cap_status` | none | rax = status | Current status |
| `cap_issue` | subject, action, resource | rax = cap_id | Issue a capability |
| `cap_evaluate` | cap_id, context | rax = verdict | Evaluate caveats + authorize |
| `cap_revoke` | cap_id | rax = result | Revoke a capability |

## Design Decisions
- Capabilities are unforgeable: issued only by the capability issuer after authz.
- Caveats are evaluated at use-time, not issue-time (dynamic attenuation).
- Revocation is immediate via capability revocation list (CRL).

## Status
Skeleton. `cap.asm` / `restrict.asm` export `cap_init`, `cap_shutdown`, `cap_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/capability test`

## License
Apache-2.0

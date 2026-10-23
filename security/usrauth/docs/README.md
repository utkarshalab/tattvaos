# security/usrauth — Identity & Access Management (IAM / Reference Monitor)

## Purpose
Central authorization subsystem for Utkarsha OS. Authentication, authorization,
RBAC, ABAC, MAC, sessions, tokens, and capability-based access control.
Implements the "Reference Monitor" pattern: many independent ways to DENY,
exactly ONE way to GRANT.

## Architecture
```
usrauth/
├── token/        # L1 - tokens, caveats, revocation
├── subject/      # L2 - subject table, transitions (handle model)
├── capability/   # L3 - capabilities, restrictions
├── policy/       # L4 - attributes, consent, relations, TTL
├── mandatory/    # L5 - integrity, MLS, TE (type enforcement)
├── audit/        # L6 - decision logging (immutable audit trail)
└── tests/        # test harness
```

## Design Invariant
> Effective authority is the INTERSECTION of every layer. If a future layer is
> added that can independently answer "yes", this model breaks — union semantics
> grant precisely what another layer meant to withhold.

Evaluation is ordered cheapest-denier-first. Correctness does not depend on
order (every term must hold), but latency does: an O(1) bitmask rejection
should never sit behind an O(depth) graph walk.

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `usrauth_init` | none | rax = 0 | Initialize reference monitor |
| `usrauth_shutdown` | none | rax = 0 | Shut down usrauth |
| `usrauth_status` | none | rax = status | Current status |
| `usrauth_authorize` | subject, action, resource | rax = verdict | Authorize (grant/deny) |
| `usrauth_authenticate` | credential | rax = result | Authenticate a subject |
| `usrauth_session_create` | subject | rax = session_id | Create a session |
| `usrauth_session_revoke` | session_id | rax = result | Revoke a session |

## Design Decisions
- Deny-by-default: any layer returning deny rejects the request.
- Every authorization decision is logged immutably (`usrauth/audit/decision_log.asm`).
- Token caveats support attenuation (scoped, time-bounded delegation).

## Threat Model
- Privilege escalation via layer bypass → mitigated by intersection semantics (no independent "grant").
- Session hijacking → mitigated by short TTL + device binding + caveats.

## Status
Skeleton. `usrauth.asm` exports `usrauth_init`, `usrauth_shutdown`, `usrauth_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth test`

## License
Apache-2.0

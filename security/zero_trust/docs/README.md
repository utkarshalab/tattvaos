# security/zero_trust — Zero Trust Architecture

## Purpose
Zero Trust network access: "never trust, always verify." Continuous
authentication, micro-segmentation, and least-privilege access enforcement.

## Architecture
- **Policy Engine** — evaluates access requests against dynamic policies
- **Policy Administrator** — establishes / tears down trust sessions
- **Policy Enforcement Point** — inline enforcement at micro-segment boundaries
- **Continuous Auth** — re-authenticates and re-authorizes on context change

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_init` | none | rax = 0 | Initialize Zero Trust |
| `zt_shutdown` | none | rax = 0 | Shut down |
| `zt_status` | none | rax = status | Current status |
| `zt_evaluate` | subject, resource, action | rax = verdict | Evaluate access request |
| `zt_session_create` | subject, context | rax = session_id | Create a trust session |
| `zt_session_revoke` | session_id | rax = result | Revoke a trust session |

## Design Decisions
- Default-deny: no access is granted without an explicit, evaluated policy match.
- Sessions are short-lived and bound to device posture + user context.
- Policy changes are hot-reloaded without dropping active sessions.

## Threat Model
- Lateral movement after compromise → mitigated by micro-segmentation + least privilege.
- Stolen session cookie → mitigated by short TTL + device posture binding.

## Status
Skeleton. `zero_trust.asm` exports `zt_init`, `zt_shutdown`, `zt_status` as no-op stubs.

## Tests
Run: `make -C security/zero_trust test`

## License
Apache-2.0

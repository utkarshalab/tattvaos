# security/ips — Intrusion Prevention System (IPS)

## Purpose
Inline intrusion prevention — actively blocks malicious traffic and suspicious
host activity in real time. Companion to the passive `ids` module.

## Architecture
- **Inspector** — inline packet/flow inspection
- **Enforcer** — drop, reset, throttle, or quarantine actions
- **Policy** — allow/deny lists, rate limits, geo-IP, reputation
- **Bypass** — fail-open/fail-closed toggle for high-availability paths

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `ips_init` | none | rax = 0 | Initialize IPS |
| `ips_shutdown` | none | rax = 0 | Shut down IPS |
| `ips_status` | none | rax = status | Current status |
| `ips_evaluate` | flow/ctx | rax = verdict | Evaluate and act on traffic |
| `ips_block` | endpoint | rax = result | Block an endpoint |
| `ips_unblock` | endpoint | rax = result | Unblock an endpoint |

## Design Decisions
- Default-deny posture: unknown traffic is blocked unless an explicit allow rule matches.
- Fail-closed by default; fail-open only when explicitly configured for HA paths.
- All enforcement actions logged to the audit subsystem.

## Threat Model
- Attacker saturates IPS with traffic → mitigated by rate-limiting + circuit breakers.
- Attacker bypasses IPS via asymmetric routing → mitigated by network placement + enforcement at choke points.

## Status
Skeleton. `ips.asm` exports `ips_init`, `ips_shutdown`, `ips_status` as no-op stubs.

## Tests
Run: `make -C security/ips test`

## License
Apache-2.0

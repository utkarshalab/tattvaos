# security/usrauth/policy — Authorization Policy Engine

## Purpose
Policy evaluation layer: attributes, consent, relations (ReBAC), and TTL-based
authorization. Feeds into the usrauth intersection model.

## Architecture
- **Attribute** — ABAC: subject/resource/environment attributes + policies
- **Consent** — user consent for data processing / actions
- **Relation** — ReBAC: subject-resource relationships (owner, editor, viewer)
- **TTL** — time-bound authorization with expiration

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `policy_init` | none | rax = 0 | Initialize policy engine |
| `policy_shutdown` | none | rax = 0 | Shut down |
| `policy_status` | none | rax = status | Current status |
| `policy_eval_attribute` | subject, action, resource | rax = verdict | ABAC attribute evaluation |
| `policy_check_consent` | subject, purpose | rax = result | Check user consent |
| `policy_check_relation` | subject, relation, resource | rax = result | ReBAC relation check |
| `policy_ttl_valid` | token, now | rax = result | Check TTL validity |

## Design Decisions
- Policy evaluation is pure (no side effects) — cacheable and deterministic.
- TTL checks use a monotonic clock to prevent rollback attacks.
- Consent records are versioned and revocable.

## Status
Skeleton. `attribute.asm` / `consent.asm` / `relation.asm` / `ttl.asm` export `policy_init`, `policy_shutdown`, `policy_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/policy test`

## License
Apache-2.0

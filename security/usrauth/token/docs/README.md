# security/usrauth/token — Tokens, Caveats & Revocation

## Purpose
Token issuance, caveat-based attenuation, and revocation for delegated
authorization in the usrauth reference monitor.

## Architecture
- **Token** — issued authorization token (subject + scope + expiry)
- **Caveat** — attenuation conditions (time window, use count, IP, resource)
- **Revoke** — token revocation list (CRL) for immediate invalidation

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `token_init` | none | rax = 0 | Initialize token subsystem |
| `token_shutdown` | none | rax = 0 | Shut down |
| `token_status` | none | rax = status | Current status |
| `token_issue` | subject, scope, ttl | rax = token_id | Issue a token |
| `token_validate` | token | rax = verdict | Validate token + caveats |
| `token_revoke` | token_id | rax = result | Revoke a token |

## Design Decisions
- Tokens are bearer objects: possession + valid caveats = authority.
- Caveats are evaluated at validation time (dynamic attenuation).
- Revocation is immediate and consults the CRL on every validation.

## Status
Skeleton. `token.asm` / `caveat.asm` / `revoke.asm` export `token_init`, `token_shutdown`, `token_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/token test`

## License
Apache-2.0

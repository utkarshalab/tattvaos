# security/usrauth/identity — Identity Providers

## Purpose
Subject identity provisioning and verification: passwords, WebAuthn, SVID,
and attestation-based identity for the usrauth reference monitor.

## Architecture
- **Password** — password-based authentication (hashed, salted)
- **WebAuthn** — FIDO2/WebAuthn roaming authenticator support
- **SVID** — SPIFFE Verifiable Identity Document (workload identity)
- **Attest** — hardware/TEE-based identity attestation

## API (skeleton)
| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `identity_init` | none | rax = 0 | Initialize identity subsystem |
| `identity_shutdown` | none | rax = 0 | Shut down |
| `identity_status` | none | rax = status | Current status |
| `identity_verify_password` | subject, password | rax = result | Verify password credential |
| `identity_verify_webauthn` | assertion | rax = result | Verify WebAuthn assertion |
| `identity_verify_svid` | svid | rax = result | Verify SVID workload identity |
| `identity_attest` | attestation | rax = result | Verify hardware attestation |

## Design Decisions
- Passwords are never stored plaintext; argon2id-hashed with per-subject salt.
- WebAuthn assertions are verified against registered credential public keys.
- SVIDs are verified against the trust root's signing keys.

## Status
Skeleton. Each provider (.asm) exports `*_init`, `*_shutdown`, `*_status` as no-op stubs.

## Tests
Run: `make -C security/usrauth/identity test`

## License
Apache-2.0

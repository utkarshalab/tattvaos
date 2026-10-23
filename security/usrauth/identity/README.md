# security/usrauth/identity — Identity Providers

> Enterprise-grade identity providers for Utkarsha OS. Password-based,
;              WebAuthn/FIDO2, SPIFFE SVID, and hardware attestation
;              authentication providers.

---

## Module Layout

```
security/usrauth/identity/
├── Makefile                    # builds all identity modules
├── .gitignore                  # module ignore rules
├── config/identity.conf        # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── identity.asm            # master dispatcher
│   ├── password.asm            # password-based authentication
│   ├── webauthn.asm            # WebAuthn/FIDO2 authentication
│   ├── svid.asm                &lt;SPIFFE SVID&gt;
│   └── attest.asm              &lt;hardware attestation&gt;
├── tests/
│   ├── run.sh                  # test runner
│   └── test_identity.asm       # skeleton test
└── bin/                        # build output (gitignored)
└── build/                      # build artifacts (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `password` | Password-based authentication | `password_init`, `password_shutdown`, `password_status`, `password_version` |
| `webauthn` | WebAuthn/FIDO2 roaming authenticator | `webauthn_init`, `webauthn_shutdown`, `webauthn_status`, `webauthn_version` |
| `svid` | SPIFFE Verifiable Identity Document | `svid_init`, `svid_shutdown`, `svid_status`, `svid_version` |
| `attest` | Hardware/TEE-based identity attestation | `attest_init`, `attest_shutdown`, `attest_status`, `attest_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Password hashing** | Passwords never stored plaintext; argon2id-hashed with per-subject salt |
| **WebAuthn assertions** | Verified against registered credential public keys |
| **SVID verification** | Verified against the trust root's signing keys |

## Build

```bash
make -C security/usrauth/identity all   # build all identity modules
make -C security/usrauth/identity test  # run all identity tests
make -C security/usrauth/identity clean # clean build artifacts
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

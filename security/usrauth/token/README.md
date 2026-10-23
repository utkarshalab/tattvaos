# security/usrauth/token — Tokens, Caveats & Revocation

> Enterprise-grade token management for Utkarsha OS. Token issuance, caveat
;              based attenuation, and revocation for delegated authorization
;              in the usrauth reference monitor.

---

## Module Layout

```
security/usrauth/token/
├── Makefile                    # builds all token modules
├── .gitignore                  # module ignore rules
├── config/token.conf           # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── token.asm               # master token dispatcher
│   ├── token.asm               # token management
│   ├── caveat.asm              &lt;caveat evaluation&gt;
│   └── revoke.asm              &lt;revocation&gt;
├── tests/
│   ├── run.sh                  # test runner
│   └── test_token.asm          # skeleton test
├── bin/                        # build output (gitignored)
└── build/                      &lt;build artifacts&gt; (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `token` | Master token dispatcher | `token_init`, `token_shutdown`, `token_status`, `token_version` |
| `caveat` | Caveat evaluation | `caveat_init`, `caveat_shutdown`, `caveat_status`, `caveat_version` |
| `revoke` | Revocation list | `revoke_init`, `revoke_shutdown`, `revoke_status`, `revoke_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Bearer objects** | Tokens are bearer objects; possession + valid caveats = authority |
| **Dynamic attenuation** | Caveats evaluated at validation time, not issue-time |
| **Immediate revocation** | Revocation is immediate via CRL lookup on every validation |

## Build

```bash
make -C security/usrauth/token all   # build all token modules
make -C security/usrauth/token test  # run all token tests
make -C security/usrauth/token clean # clean build artifacts
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

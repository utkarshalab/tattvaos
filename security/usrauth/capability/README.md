# security/usrauth/capability — Capability Management

> Enterprise-grade capability management module for Tattva OS security.
> Provides capability-based access control with unforgeable tokens,
;              dynamic attenuation via caveats, and immediate revocation.

---

## Module Layout

```
security/usrauth/capability/
├── Makefile                    # builds all capability modules
├── .gitignore                  # module ignore rules
├── config/capability.conf      # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── cap.asm                 # master capability dispatcher
│   ├── capability.asm          &lt;capability management&gt;
│   └── capability_revoker.asm  &lt;capability revocation&gt;
├── tests/
│   ├── run.sh                  # test runner
│   └── test_capability.asm     # skeleton test
└── bin/                        # build output (gitignored)
└── build/                      # build artifacts (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `capability` | Master capability dispatcher | `capability_init`, `capability_issue`, `capability_evaluate`, `capability_revoke`, `capability_status`, `capability_version` |
| `cap` | Core capability management | `cap_init`, `cap_issue`, `cap_evaluate`, `cap_revoke`, `cap_status`, `cap_version` |
| `restrict` | Capability restriction evaluator | `restrict_init`, `restrict_evaluate`, `restrict_shutdown`, `restrict_status`, `restrict_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Unforgeable tokens** | Capabilities are issued only by the capability issuer |
| **Dynamic attenuation** | Caveats evaluated at use-time, not issue-time |
| **Immediate revocation** | Capability revocation list (CRL) for immediate invalidation |

## Build

```bash
make -C security/usrauth/capability all
make -C security/usrauth/capability test
make -C security/usrauth/capability clean
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

# security/usrauth/mandatory — Mandatory Access Control (MAC)

> Enterprise-grade mandatory access control for Utkarsha OS. Implements
;              Biba-style integrity levels, Bell-LaPadula Multi-Level
;              Security (MLS), and Type Enforcement (TE). Non-discretionary;
;              subjects cannot override them.

---

## Module Layout

```
security/usrauth/mandatory/
├── Makefile                    # builds all mandatory modules
├── .gitignore                  # module ignore rules
├── config/mandatory.conf       # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── integrity.asm           # Biba-style integrity
│   ├── mls.asm                 # Multi-Level Security (Bell-LaPadula)
│   ├── te.asm                  &lt;Type Enforcement&gt;
│   └── label_manager.asm       &lt;label management&gt;
├── tests/
│   ├── run.sh                  # test runner
│   └── test_mandatory.asm      # skeleton test
└── bin/                        # build output (gitignored)
└── build/                      &lt;build artifacts&gt; (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `integrity` | Biba-style integrity (no write-up, no read-down) | `integrity_init`, `integrity_shutdown`, `integrity_status`, `integrity_version` |
| `mls` | Bell-LaPadula MLS (no read-up, no write-down) | `mls_init`, `mls_shutdown`, `mls_status`, `mls_version` |
| `te` | Type Enforcement | `te_init`, `te_shutdown`, `te_status`, `te_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Non-bypassable** | MAC is checked after discretionary (RBAC/ABAC) but before grant |
| **Immutable labels** | Labels are immutable after object creation |

## Build

```bash
make -C security/usrauth/mandatory all   # build all mandatory modules
make -C security/usrauth/mandatory test  # run all mandatory tests
make -C security/usrauth/mandatory clean # clean build artifacts
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

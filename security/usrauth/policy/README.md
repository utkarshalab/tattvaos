# security/usrauth/policy — Authorization Policy Engine

> Enterprise-grade policy engine for Tattva OS. Implements Attribute-Based
;              Access Control (ABAC), Relationship-Based Access Control
;              (ReBAC), consent management, and Time-To-Live (TTL) based
;              authorization.

---

## Module Layout

```
security/usrauth/policy/
├── Makefile                    # builds all policy modules
├── .gitignore                  # module ignore rules
├── config/policy.conf          # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── policy_engine.asm       # master policy engine
│   ├── attribute.asm           &lt;ABAC attributes&gt;
│   ├── consent.asm             &lt;consent management&gt;
│   ├── relation.asm            &lt;ReBAC relations&gt;
│   └── ttl.asm                 &lt;TTL authorization&gt;
├── tests/
│   ├── run.sh                  # test runner
│   └── test_policy.asm         # skeleton test
└── bin/                        # build output (gitignored)
└── build/                      &lt;build artifacts&gt; (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `policy` | Master policy engine | `policy_init`, `policy_shutdown`, `policy_status`, `policy_version` |
| `attribute` | ABAC attribute-based evaluation | `attribute_init`, `attribute_shutdown`, `attribute_status`, `attribute_version` |
| `consent` | User consent management | `consent_init`, `consent_shutdown`, `consent_status`, `consent_version` |
| `relation` | ReBAC relationship management | `relation_init`, `relation_shutdown`, `relation_status`, `relation_version` |
| `ttl` | Time-To-Live authorization | `ttl_init`, `ttl_shutdown`, `ttl_status`, `ttl_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Pure evaluation** | Policy evaluation is pure (no side effects) — cacheable and deterministic |
| **TTL monotonic clock** | TTL checks use monotonic clock to prevent rollback attacks |
| **Versioned consent** | Consent records are versioned and revocable |

## Build

```bash
make -C security/usrauth/policy all   # build all policy modules
make -C security/usrauth/policy test  # run all policy tests
make -C security/usrauth/policy clean # clean build artifacts
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

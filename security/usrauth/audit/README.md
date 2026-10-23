# security/usrauth/audit — Audit Decision Log

> Enterprise-grade audit decision log for Utkarsha OS. Every authorization
;              decision made by usrauth is recorded here for non-repudiation
;              and forensic traceability. Log entries are cryptographically
;              chained so tampering is detectable.

---

## Module Layout

```
security/usrauth/audit/
├── Makefile                    # builds all audit modules
├── .gitignore                  # module ignore rules
├── config/audit.conf           # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── audit_decision_log.asm  # master audit dispatcher
│   ├── audit_recorder.asm      # audit event recorder
│   └── audit_sealer.asm        # audit log sealer (hash chaining)
├── tests/
│   ├── run.sh                  # test runner
│   └── test_audit.asm          # skeleton test
├── bin/                        # build output (gitignored)
└── build/                      &lt;build artifacts&gt; (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `audit_decision_log` | Audit decision log master | `audit_init`, `audit_shutdown`, `audit_status`, `audit_version` |
| `audit_recorder` | Audit event recorder | `audit_init`, `audit_shutdown`, `audit_status`, `audit_version` |
| `audit_sealer` | Audit log sealer (hash chaining) | `audit_init`, `audit_shutdown`, `audit_status`, `audit_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Append-only** | Entries are never modified or deleted |
| **Tamper-evident** | Log-chaining: each entry includes hash of previous entry |
| **Append-only audit** | Logs are append-only; entries never modified or deleted |
| **Audit write atomicity** | Audit writes are synchronous before a decision is acknowledged |

## Build

```bash
make -C security/usrauth/audit all   # build all audit modules
make -C security/usrauth/audit test  # run all audit tests
make -C security/usrauth/audit clean # clean build artifacts
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

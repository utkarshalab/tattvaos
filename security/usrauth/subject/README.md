# security/usrauth/subject — Subject Table & Transitions

> Enterprise-grade subject table module for Tattva OS. Subject identity model
;              with handle-based references, subject state transitions, and
;              subject registry.

---

## Module Layout

```
security/usrauth/subject/
├── Makefile                    # builds all subject modules
├── .gitignore                  # module ignore rules
├── config/subject.conf         # module configuration
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   └── DESIGN.md               # design principles & state machines
├── src/
│   ├── subject.asm             # master subject dispatcher
│   ├── table.asm               # subject table
│   ├── transition.asm          &lt;subject transitions&gt;
│   └── subject_registry.asm    &lt;subject registry&gt;
├── tests/
│   ├── run.sh                  # test runner
│   └── test_subject.asm        # skeleton test
└── bin/                        # build output (gitignored)
└── build/                      &lt;build artifacts&gt; (gitignored)
```

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `subject` | Master subject dispatcher | `subject_init`, `subject_shutdown`, `subject_status`, `subject_version` |
| `table` | Subject table registry | `table_init`, `table_shutdown`, `table_status`, `table_version` |
| `transition` | Subject state transitions | `transition_init`, `transition_shutdown`, `transition_status`, `transition_version` |
| `registry` | Subject registry | `registry_init`, `registry_shutdown`, `registry_status`, `registry_version` |

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Opaque handles** | Subjects referenced by opaque handles (never raw pointers) |
| **Immutable records** | Subject records immutable once created; state changes via transitions only |
| **Logical deletion** | Subject deletion is logical (revoked), not physical |

## Build

```bash
make -C security/usrauth/subject all   # build all subject modules
make -C security/usrauth/subject test  # run all subject tests
make -C security/usrauth/subject clean # clean build artifacts
```

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

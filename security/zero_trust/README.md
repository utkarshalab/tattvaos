# security/zero_trust — Zero Trust Architecture

> **Zero Trust** — "Never trust, always verify." Continuous authentication,
> micro-segmentation, and least-privilege access enforcement for all access
> requests in Tattva OS.
>
> Zero Trust sits **on top of** `security/usrauth/` (the reference monitor
> intersection model) and adds runtime context: dynamic policies, short-lived
> trust sessions, device posture binding, continuous re-authentication, and
> micro-segmentation boundaries.

---

## Module Layout

```
zero_trust/
├── Makefile                    # builds all 8 components
├── .gitignore
├── config/zero_trust.conf      # module configuration
├── src/
│   ├── zero_trust.asm          # main dispatcher / entry point
│   ├── policy_engine.asm       # dynamic policy evaluation
│   ├── policy_administrator.asm # trust session lifecycle
│   ├── enforcement_point.asm   # inline micro-segment enforcement
│   ├── continuous_auth.asm     # re-auth on context change
│   ├── session_manager.asm     # session storage & lookup
│   ├── micro_segmentation.asm  # isolated network segments
│   └── posture_checker.asm     # device posture verification
├── include/                    # shared include files (placeholder)
├── docs/
│   ├── README.md               # this file
│   ├── API.md                  # complete API reference
│   ├── ARCHITECTURE.md         # component & layer diagrams
│   ├── DESIGN.md               # design principles & state machines
│   ├── SEQUENCE.md             # call flow diagrams
│   └── STATE_MACHINE.md        # session & policy state machines
├── tests/
│   ├── run.sh                  # test runner
│   └── test_zero_trust.asm     # skeleton test (all component inits)
└── bin/                        # build output (gitignored)
    └── build/                  # build artifacts (gitignored)
```

---

## Architecture Overview

Zero Trust extends `usrauth`'s **intersection model** (many ways to deny,
exactly one way to grant) with **runtime context**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Access Request                               │
│  subject → object, verb, context                                │
└─────────────────┬───────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│  L1: usrauth (Reference Monitor)                                │
│  Intersection of: token, subject, capability, policy,           │
│  mandatory (integrity/MLS/TE), audit                            │
└─────────────────┬───────────────────────────────────────────────┘
                  │  (usrauth says: maybe / denied)
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│  L2: zero_trust Policy Engine                                   │
│  Dynamic policies: subject, object, action, context             │
│  → verdict: ALLOW / DENY + reason code                          │
└─────────────────┬───────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│  L3: Policy Administrator                                       │
│  Session lifecycle: create, extend, revoke, validate            │
│  Session TTL: 30s default (configurable)                        │
└─────────────────┬───────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│  L4: Enforcement Point                                          │
│  Inline enforcement at micro-segment boundaries                 │
└─────────────────┬───────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│  L5: Continuous Auth + Posture Checker                          │
│  Re-authenticate on context change                              │
│  Device posture: measured boot, TPM, patch level                │
└─────────────────────────────────────────────────────────────────┘
```

---

## Components

| Component | Responsibility | Key Symbols |
|-----------|---------------|-------------|
| `zero_trust` | Main dispatcher, orchestrates all layers | `zt_init`, `zt_evaluate_access`, `zt_create_trust_session` |
| `policy_engine` | Dynamic policy evaluation (subject, object, action, context) | `zt_policy_engine_evaluate`, `zt_policy_engine_load_policy` |
| `policy_administrator` | Trust session lifecycle (create, extend, revoke, validate) | `zt_policy_admin_session_create`, `zt_policy_admin_session_revoke` |
| `enforcement_point` | Inline enforcement at micro-segment boundaries | `zt_enforcement_point_enforce`, `zt_enforcement_point_register_boundary` |
| `continuous_auth` | Re-authenticate on context change | `zt_continuous_auth_reauthenticate`, `zt_continuous_auth_check_context` |
| `session_manager` | Session storage, lookup, TTL expiry | `zt_session_manager_lookup`, `zt_session_manager_expire` |
| `micro_segmentation` | Isolated network segments, cross-segment access control | `zt_micro_segmentation_create_segment`, `zt_micro_segmentation_check_segment_access` |
| `posture_checker` | Device posture: measured boot, TPM, patch level | `zt_posture_checker_check` |

---

## Design Principles

| Principle | Requirement |
|-----------|-------------|
| **Never trust, always verify** | No implicit trust based on network location. Every request is fully authenticated, authorized, and encrypted. |
| **Least privilege** | Sessions are short-lived (30s default TTL) and bound to specific subject+object+verb+context. |
| **Fail closed** | Any component failure or timeout results in DENY. |
| **Device posture binding** | Sessions require compliant device posture (measured boot, TPM attestation, patch level). |
| **Continuous verification** | Re-authentication triggered on context change (new IP, new process, anomaly detected). |
| **Auditability** | Every access decision is logged through `usrauth/audit` with reason code. |
| **Intersection with usrauth** | zero_trust adds a layer on top of usrauth; usrauth's deny is final, zero_trust can only add more denials. |

---

## Integration with usrauth

zero_trust does **not** replace usrauth. It adds a runtime layer:

```
usrauth (static intersection)  →  zero_trust (dynamic context)
       ↓                                ↓
 token + cap + policy + MAC        dynamic policy + session + posture
 deny = final                        deny = final (union of both)
```

- If **usrauth** denies → zero_trust never evaluates (short-circuit, performance).
- If **usrauth** allows → zero_trust evaluates dynamic context (session, posture, micro-segment).
- Both must pass for access to be granted.

---

## Build

```bash
# From security/zero_trust/
make              # assemble all 8 .asm components to .bin
make test         # run skeleton tests (verifies all inits return 0)
make clean        # remove all .bin files

# From repository root
make -C security/zero_trust all
make -C security/zero_trust test
```

---

## Roadmap (Implementation)

| Phase | Work |
|-------|------|
| **Phase 1 (skeleton)** | All 8 components compile & link as stubs; tests pass. ← current |
| **Phase 2 (core)** | Implement `init`/`shutdown`/`status`, state structures, config loading, session table |
| **Phase 3 (policy)** | Dynamic policy engine, policy loading, evaluation logic |
| **Phase 4 (session + enforcement)** | Session lifecycle, enforcement point, micro-segment boundaries |
| **Phase 5 (continuous auth + posture)** | Re-authentication, device posture checking, TPM integration |

---

## License

Apache-2.0 — see `LICENSE` at the repository root.

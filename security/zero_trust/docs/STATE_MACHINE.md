# zero_trust — State Machines

## 1. Zero Trust Subsystem State Machine

```
    ┌──────────────┐
    │  UNINITIALIZED │
    └───────┬────────┘
            │ zt_init()
            ▼
    ┌──────────────┐      zt_shutdown()      ┌──────────────┐
    │   INITIALIZED  │ ─────────────────────► │   SHUTDOWN   │
    └───────┬────────┘                        └──────────────┘
            │
     ┌──────┴──────┐
     │             │
     ▼             ▼
┌──────────┐  ┌──────────────┐
│ ENABLED  │  │   DISABLED   │  ← fail-closed default
└────┬─────┘  └──────────────┘
     │
     │ access request
     ▼
┌──────────────┐
│  EVALUATING  │────┐
└──────┬─────────┘    │
       │               │
       ▼               │ error/exception
┌──────────────┐      │
│  ALLOW /     │      │
│   DENY       │──────┘
└──────────────┘
```

**State transitions:**
| From → To | Trigger | Condition |
|-----------|---------|-----------|
| UNINITIALIZED → INITIALIZED | `zt_init()` | Returns 0 |
| INITIALIZED → ENABLED | `zt_status()` | Component ready |
| INITIALIZED → SHUTDOWN | `zt_shutdown()` | Teardown |
| ENABLED → DISABLED | Policy / admin action | Explicit disable |
| ENABLED → EVALUATING | Access request | `zt_evaluate_access()` called |
| EVALUATING → ENABLED | Verdict returned | ALLOW or DENY |
| EVALUATING → SHUTDOWN | Critical failure | Component fault |

## 2. Trust Session State Machine

```
    ┌──────────────┐
    │    CREATED   │──────────────────┐
    └───────┬────────┘                │
            │ valid TTL, posture OK   │ revoked by admin
            ▼                         ▼
    ┌──────────────┐          ┌──────────────┐
    │    ACTIVE    │◀─────────│   REVOKED    │
    │  (in use)    │          └──────────────┘
    └───────┬────────┘
            │ TTL expired
            ▼
    ┌──────────────┐
    │   EXPIRED    │
    └──────────────┘
```

**Session events:**
| Event | From → To | Action |
|-------|-----------|--------|
| `session_create()` | — → CREATED | Allocate session ID, store posture hash |
| posture compliant | CREATED → ACTIVE | Mark session active |
| access within TTL | ACTIVE → ACTIVE | No state change (revalidate policy) |
| `session_revoke()` | ACTIVE → REVOKED | Mark revoked, notify IPS |
| TTL reached | ACTIVE → EXPIRED | Invalidate session |
| `session_validate()` on EXPIRED | EXPIRED → EXPIRED | Return error |

## 3. Policy Evaluation State Machine

```
    ┌─────────────────┐
    │   REQUEST       │──┐
    └───────┬─────────┘  │
            │            │ usrauth DENY (short-circuit)
            ▼            ▼
    ┌─────────────────┐ ┌─────────────────┐
    │  USRAUTH_CHECK  │ │   DENY (usrauth)│──────────┐
    └───────┬─────────┘ └─────────────────┘          │
            │ allow                                    │
            ▼                                          │
    ┌─────────────────┐                                │
    │  POLICY_MATCH   │──┐                             │
    └───────┬─────────┘  │                             │
            │ no match   │                             │
            ▼             ▼                            │
    ┌─────────────────┐ ┌─────────────────┐            │
    │   DENY (policy) │ │  POSTURE_CHECK  │──────────┐
    └─────────────────┘ └───────┬─────────┘            │
                                │ non-compliant         │
                                ▼                       │
                        ┌─────────────────┐            │
                        │ DENY (posture)  │────────────┘
                        └─────────────────┘
                                │ compliant
                                ▼
                        ┌─────────────────┐
                        │   ALLOW         │──────────────┐
                        └─────────────────┘              │
                                                         │
                                               ┌─────────┴─────────┐
                                               │   audit_log       │
                                               └───────────────────┘
```

**Verdict attribution:**
| Verdict | Reason Code | Layer |
|---------|-------------|-------|
| ALLOW | 0 | All layers passed |
| DENY | USRAUTH_DENY_* | usrauth intersection model |
| DENY | ZT_DENY_NO_SESSION | zero_trust session layer |
| DENY | ZT_DENY_SESSION_EXPIRED | zero_trust session TTL |
| DENY | ZT_DENY_POSTURE_NONCOMPLIANT | posture_checker |
| DENY | ZT_DENY_SEGMENT_BLOCKED | micro_segmentation |
| DENY | ZT_DENY_REAUTH_REQUIRED | continuous_auth |

## 4. Continuous Authentication State Machine

```
    ┌─────────────────┐
    │  AUTHENTICATED  │──────────────┐
    └─────────┬─────────┘            │
              │                      │ reauth triggered
              ▼                      ▼
    ┌─────────────────┐      ┌─────────────────┐
    │  MONITORING     │───────►│  REAUTH_PENDING │
    │  (context watch)│      └─────────┬─────────┘
    └─────────┬─────────┘              │ reauth success
              │ context unchanged      ▼
              └────────────────────► ┌─────────────────┐
                                     │ AUTHENTICATED   │
                                     │ (refreshed TTL) │
                                     └─────────────────┘
              │ context changed + reauth fail
              ▼
    ┌─────────────────┐
    │  REAUTH_FAILED  │──────────┐
    └─────────────────┘          │ revoke session
                                 ▼
                          ┌──────────────┐
                          │   REVOKED    │
                          └──────────────┘
```

## 5. Micro-segment State Machine

```
    ┌──────────────┐
    │   CREATED    │──────────────┐
    └───────┬────────┘            │
            │ segment active      │ segment deleted
            ▼                     ▼
    ┌──────────────┐      ┌──────────────┐
    │    ACTIVE    │◀─────│   DELETED    │
    │  (traffic    │      └──────────────┘
    │   allowed    │
    │  per policy) │
    └───────┬──────┘
            │
            │ cross-segment denied
            ▼
    ┌──────────────┐
    │  ISOLATED    │
    └──────────────┘
```

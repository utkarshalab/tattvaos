# zero_trust — Design

## Goals

1. **Zero implicit trust** — Network location, device ownership, or prior authentication never grants access by itself.
2. **Least privilege per request** — Each access is evaluated independently against subject, object, verb, and context.
3. **Fail closed** — Any component failure, timeout, or missing policy results in DENY.
4. **Composable with usrauth** — zero_trust adds a runtime layer on top of usrauth's static intersection model; it cannot override a usrauth deny.
5. **Audit every decision** — Every access decision emits an audit record through `usrauth/audit` with a reason code explaining WHY.

## Non-Goals

- Replacing `usrauth` — usrauth remains the authoritative deny/grant intersection.
- User-space execution — kernel-only subsystem.
- Network protocol implementation — zero_trust enforces policy; `net`/`ips` handle packets.

## Data Structures (Planned)

All mutable state resides in `.bss`, zero-initialized on load.

### zt_state_t (per-component state)

```
+---------------------+  <---
| enabled: resb 1     |      boolean enabled flag
+---------------------+
| state:   resq 1     |      opaque component state pointer
+---------------------+  <--- (varies per component)
```

### zt_policy_t (dynamic policy)

```
+---------------------+  <---
| policy_id: resq 1   |      unique policy identifier
| subject_pattern: resq 1   |      subject match pattern
| object_pattern: resq 1    |      object match pattern
| verb_mask: resd 1         |      required verb bits
| context_requirements: resq 1 |      context conditions
| ttl_ns: resq 1            |      policy lifetime
| priority: resd 1          |      evaluation priority
| next: resq 1              |      linked list
+---------------------+  <---
```

### zt_session_t (trust session)

```
+---------------------+  <---
| session_id: resq 1  |      unique session identifier
| subject_handle: resd 1 |      bound subject
| object_id: resq 1     |      bound object (or 0 = any)
| verb_mask: resd 1     |      allowed verbs
| created_ns: resq 1    |      creation timestamp
| expires_ns: resq 1    |      TTL deadline (0 = permanent, discouraged)
| posture_hash: resb 32 |      device posture hash at creation
| revoked: resb 1       |      revocation flag
| next: resq 1          |      linked list
+---------------------+  <---
```

## State Machines

### Session State Machine

```
    ┌─────────────┐
    │  CREATED    │──────┐
    └──────┬──────┘      │
           │ valid TTL   │ revoked
           ▼             ▼
    ┌─────────────┐  ┌─────────────┐
    │  ACTIVE     │◀───│ REVOKED   │
    │ (in use)    │  └─────────────┘
    └──────┬──────┘
           │ expired TTL
           ▼
    ┌─────────────┐
    │  EXPIRED    │
    └─────────────┘
```

### Policy Evaluation State Machine

```
    ┌─────────────┐
    │  RECEIVED   │──┐
    └──────┬──────┘  │
           │         │ usrauth deny
           ▼         ▼
    ┌─────────────┐ ┌─────────────┐
    │  USRAUTH    │ │  DENY       │────┐
    │  CHECK      │ │  (usrauth)  │    │
    └──────┬──────┘ └─────────────┘    │
           │ allow                    │
           ▼                          │
    ┌─────────────┐                  │
    │  POLICY     │──┐              │
    │  EVALUATE   │  │ posture fail │
    └──────┬──────┘  │              │
           │ allow   ▼              ▼
           ▼   ┌─────────────┐ ┌─────────────┐
    ┌─────────────┐ │ DENY    │ │ DENY        │
    │  ALLOW      │ │ (policy)  │ │ (posture) │
    └─────────────┘ └─────────────┘ └─────────────┘
```

## Context Factors

| Factor | Source | Used By |
|--------|--------|---------|
| Subject identity | usrauth subject table | policy_engine |
| Object identity | object descriptor | policy_engine |
| Verb (action) | USRAUTH_VERB_* | policy_engine, enforcement_point |
| Session ID | session_manager | enforcement_point |
| Device posture | posture_checker | continuous_auth, session creation |
| Network segment | micro_segmentation | enforcement_point |
| Time / TTL | monotonic clock | session_manager, policy_engine |
| Anomaly score | ids / malwarescan | continuous_auth (re-auth trigger) |

## Deny Reason Attribution

Every DENY verdict carries a reason code so audit logs explain WHY:

```
DENY_MANDATORY   → usrauth type enforcement blocked it
DENY_INTEGRITY   → subject integrity too low for object
DENY_POLICY      → no zero_trust policy matches
DENY_NO_SESSION  → no active trust session for subject
DENY_SESSION_EXPIRED → session TTL lapsed
DENY_POSTURE_NONCOMPLIANT → device failed posture check
DENY_SEGMENT_BLOCKED → cross-segment traffic not approved
DENY_REAUTH_REQUIRED → context changed, re-auth needed
```

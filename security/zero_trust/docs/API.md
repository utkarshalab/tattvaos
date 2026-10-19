# zero_trust — API Reference

## Overview

All symbols follow the NASM x86-64 calling convention:
- Callee-saved registers (`rbx`, `rbp`, `r12`–`r15`) preserved across calls.
- Return convention: `rax = 0` on success, nonzero errno-style on failure.
- All pointers are 64-bit virtual addresses.
- `usrauth.inc` decision codes are reused (`USRAUTH_ALLOW`, `USRAUTH_DENY_*`).

---

## Symbol Index

### zero_trust (main dispatcher)

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_init` | none | rax = status | Initialize Zero Trust Architecture |
| `zt_shutdown` | none | rax = status | Shut down, release all components |
| `zt_status` | none | rax = status | Current subsystem status |
| `zt_version` | none | rax = ptr | NUL-terminated version string |
| `zt_evaluate_access` | rdi=subject, rsi=object, rdx=class, rcx=verb, r8=context | rax=verdict, rbx=reason | Main access decision entry point |
| `zt_create_trust_session` | rdi=subject, rsi=context, rdx=ttl_ns | rax=session_id | Create a new trust session |
| `zt_revoke_trust_session` | rdi=session_id | rax=status | Revoke a trust session |

### policy_engine

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_policy_engine_init` | none | rax = status | Initialize policy engine |
| `zt_policy_engine_shutdown` | none | rax = status | Shut down |
| `zt_policy_engine_status` | none | rax = status | Current status |
| `zt_policy_engine_version` | none | rax = ptr | Version string |
| `zt_policy_engine_evaluate` | rdi=subject, rsi=object, rdx=class, rcx=verb, r8=context | rax=verdict, rbx=reason | Evaluate dynamic policy |
| `zt_policy_engine_load_policy` | rdi=policy_ptr, rsi=policy_size | rax=status | Load a dynamic policy at runtime |

### policy_administrator

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_policy_admin_init` | none | rax = status | Initialize administrator |
| `zt_policy_admin_shutdown` | none | rax = status | Shut down |
| `zt_policy_admin_status` | none | rax = status | Current status |
| `zt_policy_admin_version` | none | rax = ptr | Version string |
| `zt_policy_admin_session_create` | rdi=subject, rsi=context, rdx=ttl_ns | rax=session_id | Establish trust session |
| `zt_policy_admin_session_revoke` | rdi=session_id | rax=status | Revoke session |
| `zt_policy_admin_session_validate` | rdi=session_id | rax=status | Validate session (0 = valid) |

### enforcement_point

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_enforcement_point_init` | none | rax = status | Initialize enforcement point |
| `zt_enforcement_point_shutdown` | none | rax = status | Shut down |
| `zt_enforcement_point_status` | none | rax = status | Current status |
| `zt_enforcement_point_version` | none | rax = ptr | Version string |
| `zt_enforcement_point_enforce` | rdi=boundary, rsi=subject, rdx=object, rcx=verb, r8=session | rax=status | Enforce at micro-segment boundary |
| `zt_enforcement_point_register_boundary` | rdi=boundary_ptr, rsi=boundary_size | rax=boundary_id | Register a boundary |

### continuous_auth

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_continuous_auth_init` | none | rax = status | Initialize continuous auth |
| `zt_continuous_auth_shutdown` | none | rax = status | Shut down |
| `zt_continuous_auth_status` | none | rax = status | Current status |
| `zt_continuous_auth_version` | none | rax = ptr | Version string |
| `zt_continuous_auth_reauthenticate` | rdi=subject, rsi=context_change | rax=status | Re-authenticate subject |
| `zt_continuous_auth_check_context` | rdi=subject, rsi=new_context | rax=status | Check if re-auth required |

### session_manager

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_session_manager_init` | none | rax = status | Initialize session manager |
| `zt_session_manager_shutdown` | none | rax = status | Shut down |
| `zt_session_manager_status` | none | rax = status | Current status |
| `zt_session_manager_version` | none | rax = ptr | Version string |
| `zt_session_manager_lookup` | rdi=session_id | rax=session_ptr | Look up session |
| `zt_session_manager_expire` | rdi=current_time_ns | rax=count_expired | Expire past-TTL sessions |

### micro_segmentation

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_micro_segmentation_init` | none | rax = status | Initialize micro-segmentation |
| `zt_micro_segmentation_shutdown` | none | rax = status | Shut down |
| `zt_micro_segmentation_status` | none | rax = status | Current status |
| `zt_micro_segmentation_version` | none | rax = ptr | Version string |
| `zt_micro_segmentation_create_segment` | rdi=seg_ptr, rsi=seg_size | rax=segment_id | Create isolated segment |
| `zt_micro_segmentation_check_segment_access` | rdi=src_seg, rsi=dst_seg, rdx=verb | rax=status | Check cross-segment access |

### posture_checker

| Symbol | Input | Output | Description |
|--------|-------|--------|-------------|
| `zt_posture_checker_init` | none | rax = status | Initialize posture checker |
| `zt_posture_checker_shutdown` | none | rax = status | Shut down |
| `zt_posture_checker_status` | none | rax = status | Current status |
| `zt_posture_checker_version` | none | rax = ptr | Version string |
| `zt_posture_checker_check` | rdi=device, rsi=req_ptr, rdx=req_count | rax=status | Check device posture |

---

## Error Codes

Reuses `usrauth.inc` verdict codes:

| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | `USRAUTH_ALLOW` | Access granted |
| -1 | `USRAUTH_DENY_MANDATORY` | L5 type enforcement denial |
| -2 | `USRAUTH_DENY_INTEGRITY` | L2 integrity (no write-up) |
| -3 | `USRAUTH_DENY_MLS` | L5 MLS (no read-up / write-down) |
| -4 | `USRAUTH_DENY_CAPABILITY` | L3 capability not held |
| -5 | `USRAUTH_DENY_CAVEAT` | L1 token caveat unsatisfied |
| -6 | `USRAUTH_DENY_EXPIRED` | L1/L4 grant lapsed |
| -7 | `USRAUTH_DENY_POLICY` | L4 no relation grants it |
| -8 | `USRAUTH_DENY_REVOKED` | L1 token epoch stale |
| -9 | `USRAUTH_DENY_INVALID` | Malformed request |
| -10 | `USRAUTH_DENY_FORGED` | L1 token tag did not authenticate |

Zero Trust-specific reason codes (returned in `rbx`):

| Code | Meaning |
|------|---------|
| -100 | `ZT_DENY_NO_SESSION` | No active trust session |
| -101 | `ZT_DENY_SESSION_EXPIRED` | Session TTL lapsed |
| -102 | `ZT_DENY_POSTURE_NONCOMPLIANT` | Device posture failed |
| -103 | `ZT_DENY_SEGMENT_BLOCKED` | Micro-segment boundary denied |
| -104 | `ZT_DENY_REAUTH_REQUIRED` | Context change requires re-auth |
| -105 | `ZT_DENY_POLICY_NOT_FOUND` | No matching dynamic policy |

---

## Build

```bash
make -C security/zero_trust all
make -C security/zero_trust test
```

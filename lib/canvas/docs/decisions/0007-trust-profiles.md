# Decision 0007: Trust Profiles and Capability Gating

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (implemented C17)

## Context
Canvas runs in a single address space with software isolation. Not all clients are equal — a panel needs more privileges than a sandboxed app. Need a declarative, auditable model.

## Decision
**Trust Profiles** — Declarative capability bundles loaded from `conf/profiles/*.profile`:

```
profile Trusted   { caps: ALL,           quota: unlimited, prompts: never }
profile Standard  { caps: CORE+SHELL+INPUT+DATA, quota: 64MB,  prompts: privileged }
profile Sandboxed { caps: CORE+SHELL+INPUT,       quota: 16MB,  prompts: all }
profile Remote    { caps: CORE+SHELL+INPUT+REMOTE, quota: 32MB,  prompts: all }
profile Kiosk     { caps: CORE+SHELL+INPUT,       quota: 8MB,   prompts: never }
```

**Capability Gating**:
- At connect: client sends wanted caps → server grants subset per profile
- Ungranted interfaces: **invisible** to client (bind returns `ENOENT`)
- Privileged caps (`CAPTURE`, `INJECT`, `POLICY`, `DEBUG`, `SESSION_LOCK`) require:
  - Trust profile grant AND
  - Explicit runtime grant (audit log entry) AND
  - Server-drawn permission prompt (for interactive)

**Capability Tokens** — Unguessable `u64` from `tv_entropy`, authenticated with siphash key:
- Used for: `cw_policy` external process auth, `cw_capture` session tokens
- Verified on every privileged call

**Audit Log** — Append-only ring buffer:
```
struct AuditEntry { time_ns, client_id, action, cap, result, details }
```
Written for: connect/disconnect, cap grant/deny, privileged call, policy change.

## Rationale
| Model | Problems | Canvas Fix |
|-------|----------|------------|
| **X11: None** | Any client keylogs, screenshots, injects | Default deny, explicit grant |
| **Wayland: Ad-hoc** | Each compositor invents own (xdg-desktop-portal, etc.) | Unified profiles + protocol |
| **SELinux/AppArmor** | Complex, process-based, not protocol-aware | Protocol-level, per-interface |
| **Flatpak portals** | DBus, separate daemon, async | In-process, synchronous, audited |

**Server-drawn prompts** (not client-drawn) because:
- Cannot be spoofed/overlaid
- Visually distinct (trusted path)
- Accessible (high contrast, screen reader hooks)

## Consequences
- `inc/trust.inc`, `inc/quota.inc` — Structures
- `src/security/profile_load.asm` — Parse `conf/profiles/*.profile`
- `src/security/gate.asm` — Capability check on every dispatch
- `src/security/token.asm` — Siphash token gen/verify
- `src/security/audit.asm` — Append-only log
- `src/security/prompts.asm` — Server-drawn permission UI
- `proto/canvas-capture.cwp`, `canvas-inject.cwp`, `canvas-policy.cwp`, `canvas-debug.cwp`, `canvas-session.cwp` — Privileged interfaces

## Related
- `architecture.md` §10, §11.1
- Decision 0004 (handles), 0008 (isolation)
- `conf/profiles/*.profile`

## Revisit Criteria
If hardware domains (paging, ring 3) added to Tattva → profiles map to domain permissions, not just software caps.
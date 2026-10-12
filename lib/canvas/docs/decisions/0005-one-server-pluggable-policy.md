# Decision 0005: One Server, Pluggable Policy

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (implemented C13)

## Context
Window management policy (tiling, floating, focus, workspaces) is a major source of fragmentation in Wayland (every compositor reimplements) and races in X11 (separate WM process).

## Decision
**Single `canvasd` server process** with **pluggable policy module**:
- Built-in policies: Floating (stacking), Tiling (binary tree), Kiosk (single max)
- External policy: Separate process speaking `cw_policy` interface (same isolation as clients)
- Policy selected at startup via `policy.conf` or per-seat
- Hot-reloadable (policy process can restart without server restart)

**Policy Interface** (`policy_iface.asm`):
```c
struct PolicyIface {
  layout(output, windows) -> LayoutResult
  configure(toplevel, desired) -> actual
  focus_change(old, new)
  new_window(toplevel)
  close_window(toplevel)
}
```

**Server owns**: Surface tree, z-order, input focus, output layout, damage tracking
**Policy owns**: Window placement, sizing, workspace logic, focus policy

## Rationale
| Model | Problems | Canvas Fix |
|-------|----------|------------|
| **X11: Separate WM** | Race on map/configure, focus stealing, no atomicity | Single server = atomic commit includes policy decisions |
| **Wayland: Baked-in** | Every DE (GNOME, KDE, Sway, Hyprland) reimplements tiling, gaps, rules | One policy API; built-in covers 90%; external for custom |
| **No policy (raw)** | Clients fight for position, no consistency | Policy mediates all configure requests |

**External policy via `cw_policy`** (not in-process plugin) because:
- Same isolation as clients (handle checks, quotas)
- Can be written in any language (eventually)
- Crash only kills policy, not server
- Audit trail for privileged policy actions

## Consequences
- `src/shell/` — Roles, states, configure/ack transactions
- `src/policy/` — Built-in policies + `policy_external.asm` bridge
- `proto/canvas-policy.cwp` — External policy protocol
- `conf/policy.conf` — Policy selection + options
- `conf/rules.conf` — Per-app rules (match class/title → policy hints)

## Related
- `architecture.md` §9
- Decision 0006 (atomic commit includes policy)
- `proto/canvas-shell.cwp`, `proto/canvas-policy.cwp`

## Revisit Criteria
If policy API proves insufficient for advanced layouts (tabbed, master/stack, floating rules), extend `cw_policy` v2. Current design supports binary tree tiling + floating + rules.
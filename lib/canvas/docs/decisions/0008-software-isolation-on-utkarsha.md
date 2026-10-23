# Decision 0008: Software Isolation on Utkarsha

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (foundation for C1, C4, C5, C17)

## Context
Utkarsha OS is a ring-0 unikernel — Canvas and all clients share **one address space**. No MMU isolation, no ring 3, no process separation yet.

## Decision
**Software Isolation Model** — Five layers:

### 1. Handles Only (Decision 0004)
- Clients never hold raw pointers into server memory
- Every object = generation-tagged handle validated on every access
- Stale handle → trap, not corruption

### 2. Channels, Not Shared State
- Client↔Server communication = bounded SPSC rings
- **Payload ring**: Messages (header + body)
- **Handle ring**: Handle arrays (never in payload)
- Bulk data (pixels) = explicit `cw_buffer` with ownership transfer
- No shared memory regions between client and server

### 3. Per-Client Arenas
- Each client gets dedicated `Arena` at connect
- Sized by trust profile quota (e.g., 64 MB Standard, 16 MB Sandboxed)
- All client allocations (objects, strings, message buffers) from this arena
- On disconnect: entire arena freed in O(1) — no leak tracking needed

### 4. Verified Clients (RSO)
- Clients **must** be built with Utkarsha toolchain
- Register Ownership (RSO) rules prevent:
  - Forging handles (no arbitrary `u32` → handle casts)
  - Out-of-bounds memory access
  - Control-flow hijack
- Server trusts **only verified client images**

### 5. Fault Containment
- Trap in client (invalid handle, OOB, div/0) → **only that client torn down**
- Server continues; other clients unaffected
- `ut_task` provides task boundary for future HW domain migration

## What This Gives You
| Threat | Mitigated? | How |
|--------|------------|-----|
| Client reads other's pixels | **Yes** | Buffers owned by handle; release fence required |
| Client observes unrelated input | **Yes** | Focus/hit-test enforced in server |
| Client injects input | **Yes** | `cw_inject` requires privileged grant |
| Client forges handles | **Yes** | Generation check + RSO verifier |
| Client exhausts memory | **Yes** | Per-client arena quota |
| Client stalls server | **Yes** | Bounded rings, slow client disconnected |
| **Malicious machine code** | **No** | RSO verifier only as strong as its rules |

## What This Does NOT Give You
- **Defence against hostile binaries** — If you load unverified code, it can corrupt Canvas memory
- **Side-channel resistance** — No cache/timing isolation
- **Kernel compromise containment** — Canvas runs in ring 0

## Consequences
- **No untrusted third-party binaries** until Utkarsha has HW domains
- `inc/arena.inc`, `src/core/arena.asm` — Bump allocators with quotas
- `inc/channel.inc`, `src/proto/channel.asm` — SPSC rings
- `src/security/isolation.asm` — Handle checks, ownership rules
- `src/security/verifier_hooks.asm` — RSO verification integration points
- `tests/unit/test_isolation.asm` — Isolation invariant tests

## Migration Path to Hardware Domains
When Utkarsha adds paging/ring 3:
1. Each client → separate address space (task)
2. Channels → shared memory + eventfd (or Utkarsha IPC)
3. Handles → capability table (kernel-enforced)
4. Arenas → per-process heaps
5. **CWP protocol unchanged** — only transport layer changes

## Related
- `architecture.md` §3
- Decision 0004 (handles), 0007 (trust profiles)
- `utkarsha-contract.md` §3.5 (ut_task, ut_wait)

## Revisit Criteria
When Utkarsha implements hardware protection domains → migrate isolation model incrementally. Protocol and server architecture remain valid.
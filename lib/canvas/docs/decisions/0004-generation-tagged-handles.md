# Decision 0004: Generation-Tagged Handles

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (implemented C1)

## Context
Canvas and clients share a single address space (Tattva is ring-0 unikernel). Object references must be safe against use-after-free and stale references.

## Decision
**Handle Format** (32-bit):
```
bits 31..20: generation (12 bits = 4096 wraps)
bits 19..0:  index (20 bits = 1,048,576 objects per table)
```

**Handle Table** (per client + global):
- Array of `HandleEntry { obj_ptr, generation }`
- On `create`: allocate slot, increment generation, return `(gen<<20)|idx`
- On `destroy`: null `obj_ptr`, increment generation (slot reusable)
- On `resolve`: check `entry.generation == handle>>20` → return `obj_ptr` or NULL

**Every object access validates generation** — stale handles trap immediately.

## Rationale
| Alternative | Why Rejected |
|-------------|--------------|
| **Raw pointers** | Use-after-free = memory corruption, exploit |
| **Simple integer IDs** | Reuse after free → stale ID accesses new object |
| **Capability pointers (CHERI)** | Not available on x86-64 |
| **Epoch-based reclamation** | Complex, still needs generation check |
| **64-bit handles** | Wasteful; 32-bit fits in register, cache-friendly |

**12-bit generation** chosen because:
- 4096 wraps per slot before reuse
- At 1M ops/sec per slot: 4096 seconds (~1 hour) before wrap
- Realistic wrap rate << 1M/sec → practically never wraps
- If wrap occurs: generation match fails → safe NULL return

**Per-client handle tables** because:
- Client A cannot guess Client B's handles (different tables)
- Server global table for server-owned objects (outputs, seats)
- Tables destroyed on client disconnect → all handles invalidated

## Consequences
- `inc/handle.inc` — Handle table macros, create/resolve/destroy
- `src/core/handle.asm` — Implementation
- Every dispatch: `handle_resolve` before object access
- Handle channel carries raw `u32` handles — validated on receive
- Fuzzing: `tests/fuzz/fuzz_objects.asm` tests generation wrap, stale access

## Implementation
```nasm
; handle_create(table, obj_ptr) -> handle (0=fail)
; handle_resolve(table, handle) -> obj_ptr (0=invalid)
; handle_destroy(table, handle) -> 0 OK
; handle_table_init(table, arena, capacity)
; handle_table_free(table)
```

## Related
- `architecture.md` §3.2
- Decision 0003 (wire protocol), 0008 (software isolation)
- `inc/handle.inc`, `src/core/handle.asm`

## Revisit Criteria
If object density exceeds 1M per table → 64-bit handles (44-bit index, 20-bit generation). Unlikely.
# Decision 0006: Explicit Sync in v1

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (implemented C6, C7, C8)

## Context
Synchronization between client rendering, server composition, and display scanout is the #1 source of tearing, stutter, and frame latency in X11 and early Wayland.

## Decision
**Explicit synchronization from v1** — no implicit flushes, no undefined behavior.

**Primitives**:
- `cw_fence` — Binary fence (signaled/unsignaled), GPU/CPU waitable
- `cw_timeline` — Monotonic timeline with 64-bit points, GPU/CPU waitable
- Every `cw_buffer` carries: `acquire_fence`, `release_fence`, optional `timeline` + points

**Flow**:
```
Client render → signal acquire_fence → cw_surface.attach(buffer, acquire_fence)
Server commit → wait acquire_fence → composite → signal release_fence
Client reuse → wait release_fence → render next frame
```

**Atomic commit** (`cw_surface.commit` with `TRANSACTION` flag):
- All pending surface state applied at single frame boundary
- No partial updates visible
- Frame callbacks fired after commit applied
- Presentation feedback queued for committed frame

## Rationale
| Model | Problems | Canvas Fix |
|-------|----------|------------|
| **X11: Implicit** | No sync → tearing, double-buffer race | Explicit fences on every buffer |
| **Wayland v1: Implicit** | `wl_surface.commit` no sync → compositor guesses | Explicit acquire/release from day one |
| **Wayland later: explicit sync** | Added late, fragmented (dma_fence, sync_file, timeline) | Unified `cw_fence` + `cw_timeline` in v1 |
| **Vulkan: VkFence/VkSemaphore** | Good but GPU-only | CPU-waitable, works with SW renderer |

**Timeline points** (not just binary fences) because:
- Multi-buffer pipelines (triple buffer + async compute)
- Client can signal "frame N ready" without waiting for "frame N-2 displayed"
- Server can schedule composition based on timeline progress
- Matches DRM syncobj / Vulkan timeline semaphores

## Consequences
- `inc/fence.inc`, `inc/buffer.inc` — Structures
- `src/server/fence.asm`, `src/server/timeline.asm` — Implementation
- `src/server/buffer.asm` — Ownership transfer with fences
- `src/server/commit.asm` — Atomic commit waits acquire, signals release
- `src/render/compositor.asm` — Waits fences before reading buffers
- `src/client/buffer_helpers.asm` — Client-side fence management

## Related
- `architecture.md` §4.4, §5
- Decision 0003 (wire protocol carries fence handles), 0002 (buffer format)
- `proto/canvas-core.cwp` — `cw_buffer`, `cw_fence`, `cw_timeline`
- `proto/canvas-present.cwp` — Presentation feedback

## Revisit Criteria
If GPU driver (C24) requires different sync primitive (dma_fence, sync_file), add translation layer in `ut_mmio`/`gpu_fence.asm`. CWP protocol remains unchanged.
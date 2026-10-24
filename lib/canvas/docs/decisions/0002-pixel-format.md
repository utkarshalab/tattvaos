# Decision 0002: Pixel Format — 32-bit BGRX/BGRA Premultiplied Alpha

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0

## Context
Need a single canonical pixel format for:
- Client buffers
- Compositor internal surfaces
- Scanout to display hardware
- Cursor/overlay planes
- Screenshot/capture

## Decision
**Primary format**: `DRM_FORMAT_BGR8888` (32-bit BGRX, little-endian)  
**With alpha**: `DRM_FORMAT_BGRA8888` (32-bit BGRA, premultiplied alpha)  
**All internal rendering**: Premultiplied alpha, linear or sRGB per buffer metadata

No other formats in v1 core. Additional formats (RGB565, YUV, 10-bit) negotiated per-buffer via `cw_buffer.create` with modifier list.

## Rationale
| Format | Pros | Cons | Verdict |
|--------|------|------|---------|
| **BGRA8888 premul** | GPU-native, blend-friendly, single format | 33% larger than RGB565 | **Primary** |
| RGBA8888 | Common in SW | GPU swizzle needed | No |
| RGB565 | 16-bit, smaller | No alpha, banding | Negotiated only |
| RGB10A2 | 10-bit color | Not all HW supports | Negotiated only |
| YUV420 | Video efficient | Complex sampling | Via dmabuf import (C24) |

**Premultiplied alpha** chosen because:
- `dst = src + dst * (1 - src_a)` — single blend equation
- No division, no branch on alpha
- SIMD-friendly (pmaddubsw, vpmaddubsw)
- Associative for multi-layer composition

## Consequences
- All client buffers must be BGRA8888 or negotiated
- `blend.asm` / `blend_*.asm` assume premultiplied input
- `cw_buffer.format` defaults to `DRM_FORMAT_BGR8888` (opaque) or `DRM_FORMAT_BGRA8888`
- Color management (C25) converts to/from this format at scanout

## Implementation
- `inc/color.inc` — Format constants, premul/unpremul helpers
- `lib/ugfx/core/blend.asm` — Scalar premul blend
- `lib/ugfx/core/blend_sse2/avx2/avx512.asm` — SIMD premul blend
- `src/render/sw_render.asm` — Compositor uses premul throughout

## Related
- `architecture.md` §5.1, §13
- Decision 0010 (GPU family — format modifiers)
- `proto/canvas-core.cwp` — `cw_buffer.create` format/modifier negotiation

## Revisit Criteria
If a major deployment target lacks BGRA8888 scanout support, add format translation in backend. Unlikely on modern x86 GPUs.
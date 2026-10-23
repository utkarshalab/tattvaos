# Decision 0010: First Display and GPU Family — One at a Time

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (guides C10, C24)

## Context
Writing display/GPU drivers is the largest effort in Canvas (~23k lines for one family). Cannot support all hardware.

## Decision
**Support exactly ONE display engine family and ONE GPU family** for native backend and GPU acceleration, chosen from deployment hardware.

### Display Engine Family (C10 — Native Backend)
**Criteria for selection**:
1. Deployment target has this hardware
2. Public register documentation available (or NDA obtained)
3. Supports: atomic modeset, planes (cursor + ≥1 overlay), VRR, HDR metadata
4. Reasonable register complexity (not 5000+ registers)

**Candidate families** (pick ONE):
| Family | Pros | Cons |
|--------|------|------|
| **AMD DCN (Display Core Next)** | Open docs, atomic, planes, VRR, HDR, used in APUs | Complex (multiple DCE versions) |
| **Intel Display (Gen9+)** | Open docs, atomic, planes, VRR | Many variants, complex power mgmt |
| **NVIDIA (Tegra/Orin)** | Good docs for embedded | Proprietary, NDA for desktop |
| **Simple KMS (ARM SoCs)** | Simpler registers | Not x86 PC deployment |

**Recommendation**: **AMD DCN** (e.g., Renoir/Cezanne/Rembrandt APU) — best doc availability, covers laptop/desktop/server, single family spans multiple products.

### GPU Family (C24 — GPU Acceleration)
**Same hardware as display engine** (integrated GPU preferred):
- **AMD GFX9/GFX10** (RDNA) — Matches DCN APUs
- Unified memory, no separate VRAM management
- Compute shaders for composition, blit/fill engines for 2D

**If discrete GPU needed later**: Add second family (NVIDIA/Intel discrete) as separate `src/gpu/family/` tree.

## Implementation Strategy

### C10: Native Backend (Display Only)
```
src/backend/family/amd/dcn/
  ├── dcn_regs.inc       ; Register offsets, bitfields
  ├── dcn_modeset.asm    ; Atomic commit to HW
  ├── dcn_planes.asm     ; Cursor + overlay setup
  ├── dcn_vblank.asm     ; Vblank IRQ, timestamps
  ├── dcn_flip.asm       ; Page flip
  ├── dcn_edid.asm       ; EDID via I2C/AUX
  └── dcn_hotplug.asm    ; HPD IRQ handling
```
- `fb_linear` (C9) works on ALL hardware (VBE/UEFI GOP) — fallback
- `headless` (C9) works without ANY display HW — tests/CI

### C24: GPU Acceleration (Compute/Blit)
```
src/gpu/family/amd/gfx9/
  ├── gfx9_regs.inc      ; Register defs
  ├── gfx9_ring.asm      ; Command ring (GFX/COMPUTE/SDMA)
  ├── gfx9_blit.asm      ; SDMA blit/fill
  ├── gfx9_mem.asm       ; GTT/VRAM, buffer placement
  └── gfx9_fence.asm     ; Timeline semaphores
```
- `sw_render` (C8) is reference — **always works**
- Direct scanout (C8) + hardware planes (C10) recover 80% of GPU benefit
- GPU only needed for: complex shaders, heavy multi-layer, HDR tonemap

## Consequences
- **No hardware abstraction layer** — family code IS the driver
- `src/backend/family/` and `src/gpu/family/` are **not shared** — each family independent
- Build system: `make FAMILY=amd/dcn` selects family
- CI tests on chosen hardware; other families = compile-check only

## Related
- `architecture.md` §6.1, §6.2
- Decision 0009 (driver boundary), 0002 (pixel format)
- `PLAN.md` Track C10, C24

## Revisit Criteria
- If deployment target changes → swap family (rewrite C10/C24 family code)
- If Utkarsha gains GPU virtualization → add mediated pass-through
- Multiple families only if business case justifies ~15k lines each
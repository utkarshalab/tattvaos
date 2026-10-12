# Decision 0009: Driver Boundary — Tattva Owns Buses, Canvas Owns Display Engines

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0 (implemented C9, C10, C24)

## Context
Who programs the display controller? Who manages GPU? Tattva kernel or Canvas?

## Decision
**Clean split at the display engine / GPU boundary**:

| Tattva Kernel Owns | Canvas Owns |
|--------------------|-------------|
| PCI bus enumeration | Display controller register programming |
| PCI config space access | Mode setting (CRTC, encoder, connector) |
| MSI/MSI-X interrupt allocation | Vblank interrupt handling |
| MMIO region mapping (via `tv_mmio_map`) | Page flip (atomic commit to HW) |
| DMA coherent allocation (via `tv_dma_alloc`) | Hardware plane assignment (cursor, overlay) |
| IOMMU domain management | EDID parsing, DDC/I2C |
| GPU reset / power management | GPU command ring submission (C24) |
| Generic HID/USB/PS2 drivers | Input interpretation (keymap, focus, accel) |

**Canvas binds to Tattva services** (see `tattva-contract.md`):
- `tv_pci` — Enumerate, find display class devices
- `tv_mmio` — Map BARs, read/write registers
- `tv_irq` — Register vblank, GPU completion handlers
- `tv_dma` — Allocate scanout buffers, GPU command buffers
- `tv_input` — Raw input events from HID drivers

## Rationale
| Alternative | Problems | Canvas Fix |
|-------------|----------|------------|
| **Kernel modeset (Linux DRM/KMS)** | Kernel grows display logic, policy in kernel | Canvas owns modeset → atomic commit in userspace |
| **Userspace GPU driver (Mesa)** | Complex, duplicated per GPU | One GPU family at a time (C24), direct HW control |
| **Firmware/UEFI GOP only** | No mode switching, no planes, no VRR | Boot FB (C9) → Native modeset (C10) |
| **Tattva owns everything** | Kernel bloat, slow iteration | Thin `tv_*` bindings, Canvas = display server |

**Why Canvas owns display engine programming**:
- Atomic commit (surface + policy + mode) must be single transaction
- Frame scheduling (vblank-aligned) needs direct HW control
- Plane assignment (overlay for video, cursor) is policy decision
- Hotplug response must update scene graph atomically

**Why Tattva owns buses**:
- PCI/USB/ACPI are generic, not display-specific
- Security: Canvas doesn't touch config space directly
- Portability: Tattva abstracts bus differences

## Consequences
- `src/tattva/tv_pci.asm`, `tv_mmio.asm`, `tv_irq.asm`, `tv_dma.asm`, `tv_input.asm` — Thin wrappers
- `src/backend/native_pci.asm` — PCI discovery for display class
- `src/backend/native_modeset.asm` — CRTC/encoder/connector programming
- `src/backend/native_flip.asm` — Page flip via HW registers
- `src/backend/native_vblank.asm` — Vblank IRQ → frame clock
- `src/backend/native_planes.asm` — Overlay/cursor plane setup
- `src/backend/edid.asm`, `ddc.asm` — EDID parse, I2C read
- `src/backend/family/<vendor>/<family>/` — Per-family register definitions

## GPU Boundary (C24)
| Tattva | Canvas |
|--------|--------|
| PCI BAR mapping, IOMMU | Command ring allocation, submission |
| GPU reset, power | Fence/syncobj management |
| Memory allocation (VRAM/GTT) | Buffer placement, tiling, modifiers |
| Interrupt (completion) | Timeline semaphore signaling |

## Related
- `tattva-contract.md` §3.10, §3.11
- `architecture.md` §6.2
- Decision 0010 (first family), 0002 (pixel format)
- `proto/canvas-output.cwp` — `cw_output` modeset/planes

## Revisit Criteria
If Tattva gains a generic "display driver framework" → re-evaluate. Current split minimizes kernel complexity while giving Canvas full control.
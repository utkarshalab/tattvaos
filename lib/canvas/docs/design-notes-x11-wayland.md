# Design Notes: What Canvas Borrows and Avoids from X11 and Wayland

**Purpose**: Document design rationale. Not a specification — see `architecture.md` and `proto/*.cwp` for that.

---

## 1. Executive Summary

| Aspect | X11 | Wayland | Canvas |
|--------|-----|---------|--------|
| **Architecture** | Client-server, network-transparent | Compositor = server, no network | Single-address-space, channels, no network transparency |
| **Window Management** | Separate WM process | Compositor bakes it in | Pluggable policy (in-process or `cw_policy` process) |
| **Rendering** | XRender, GLX, DRI | EGL/GBM, compositor-owned | Explicit renderer interface, SW + GPU backends |
| **Synchronization** | Implicit, broken | Explicit sync (recent) | Explicit sync from v1 (fences, timelines, atomic commit) |
| **Input** | Global grab, keyloggers easy | Focus follows keyboard, no global shortcuts | Focus-gated, mediated shortcuts, no snooping |
| **Security** | None | Per-compositor extensions | Capability-based, trust profiles, audit log |
| **Remote** | X11 protocol | PipeWire, compositor-specific | Built-in RFB+TLS + native CRP |
| **Observability** | Limited | Compositor-specific | Trace, frame timeline, record/replay, CTS |

---

## 2. What Canvas Borrows (Good Ideas)

### 2.1 From X11
| Idea | Canvas Adaptation |
|------|-------------------|
| **Network transparency concept** | Not network, but **channel abstraction** — same protocol works in-process, cross-process, cross-machine (remote) |
| **Extension mechanism** | **Capability-negotiated interfaces** — every feature is an interface with version, not a bolt-on |
| **Property/atom system** | **No** — replaced by typed CWP messages, no stringly-typed props |
| **Colormap/visual model** | **No** — single pixel format (BGRA premul), color management via ICC per-output |

### 2.2 From Wayland
| Idea | Canvas Adaptation |
|------|-------------------|
| **Compositor owns frame** | **Yes** — server drives composition, clients don't flip |
| **Buffer ownership transfer** | **Yes** — explicit attach/release with fences |
| **Subsurfaces** | **Yes** — `cw_subsurface` for video, cursors, popups |
| **Relative pointer / pointer constraints** | **Yes** — `cw_pointer.lock`, `confine` |
| **Touch/gesture protocol** | **Yes** — `cw_touch`, `cw_gestures` (pinch, swipe, rotate) |
| **Tablet protocol** | **Yes** — `cw_tablet` (pressure, tilt, rotation, tool type) |
| **Output configuration** | **Yes** — `cw_output` with modes, scale, rotation, VRR |
| **Presentation feedback** | **Yes** — `cw_present` with refresh, flags, sequencer |
| **Data device (clipboard/DnD)** | **Yes** — `cw_data` with MIME negotiation, limits |
| **Input method protocol** | **Yes** — `cw_text` + `cw_preedit` |
| **Accessibility hooks** | **Yes** — `cw_a11y` tree + events |
| **Layer shell (panels, lock, OSD)** | **Yes** — `cw_layer` with z-layers |
| **Fractional scaling** | **Yes** — `wp_fractional_scale` → `cw_surface.scale` (fixed-point) |
| **DRM lease / KMS** | **Concept only** — Canvas owns display engine directly via `tv_pci`/`tv_mmio` |

### 2.3 From Modern Graphics (Vulkan, DRM/KMS, GBM)
| Idea | Canvas Adaptation |
|------|-------------------|
| **Explicit sync (VkFence, sync_file)** | **Yes** — `cw_fence` + `cw_timeline` from day one |
| **Atomic commit (KMS atomic)** | **Yes** — `cw_surface.commit` + transaction flag |
| **Plane assignment (overlay, cursor)** | **Yes** — `render.inc` + `backend.inc` plane interface |
| **Direct scanout (zero-copy fullscreen)** | **Yes** — `direct_scanout.asm` fast path |
| **Buffer modifiers / format negotiation** | **Yes** — `cw_buffer.create` with format + modifier list |
| **HDR metadata (ST.2084, HLG)** | **Yes** — `colorm.inc` + `cw_output.hdr_metadata` |

---

## 3. What Canvas Explicitly Avoids (Bad Ideas)

### 3.1 From X11
| Anti-Pattern | Why Avoid | Canvas Alternative |
|--------------|-----------|-------------------|
| **Global coordinate space** | Security, multi-monitor complexity | Per-surface local coords; server composes |
| **GrabServer / passive grabs** | Deadlocks, input starvation | Focus-gated input, mediated shortcuts |
| **Property/atom string matching** | Slow, insecure, no schema | Typed binary protocol (cwpgen) |
| **XRender / core fonts** | Legacy, no GPU path | TrueType (C22) + SIMD blend |
| **GLX / indirect rendering** | Overhead, security | Direct buffer sharing, explicit sync |
| **Xinerama / RandR 1.x** | Broken multi-head | `cw_output` with explicit layout |
| **Network transparency in protocol** | Latency, complexity | Separate remote protocol (RFB/CRP) |
| **No frame scheduling** | Tearing, jank | Frame clock per output, vblank-aligned |
| **Client-side decorations (forced)** | Inconsistent, spoofable | Negotiated: server or client (`cw_decoration`) |
| **No input method protocol (XIM broken)** | Poor IME support | `cw_text` from Wayland design |

### 3.2 From Wayland
| Anti-Pattern | Why Avoid | Canvas Alternative |
|--------------|-----------|-------------------|
| **Compositor reimplements everything** | Fragmentation, bugs | **One server, pluggable policy** (`cw_policy`) |
| **No standard window management** | Every DE writes own tiling | Built-in floating/tiling/kiosk + external policy |
| **No standard decorations** | CSD/SSD mess | Negotiated `cw_decoration` with theme engine |
| **No standard screenshot/capture** | PipeWire dependency | `cw_capture` (privileged, audited) |
| **No standard input injection** | Automation broken | `cw_inject` (privileged, audited) |
| **No standard remote desktop** | PipeWire/RDP fragmentation | Built-in RFB+TLS + CRP |
| **No conformance suite** | "Works on my compositor" | `tests/cts/` — mandatory for v1 |
| **No record/replay** | Debugging compositor bugs hard | Deterministic `.cwprec` replay |
| **No resource governance** | OOM, DoS possible | Quotas, rate limits, watchdog (C19) |
| **Global registry (wl_registry)** | Round-trip on connect | Capability bitmap in handshake, no registry round-trip |
| **Listener callbacks (C ABI)** | Not for assembly | Message rings + opcode dispatch tables |
| **Shared memory (wl_shm) only** | No GPU buffer sharing | `cw_buffer` with DMA, modifiers, fences |
| **No HDR/color management in core** | Added late, fragmented | `colorm.inc` + ICC in v1 |

### 3.3 From Both (General)
| Anti-Pattern | Canvas Fix |
|--------------|------------|
| **C ABI / libc dependency** | Pure assembly, Tattva syscalls only |
| **Dynamic linking** | Static image, no relocations at runtime |
| **Unbounded memory growth** | Per-client arenas, quotas, buffer-age |
| **Implicit synchronization** | Explicit fences/timelines everywhere |
| **Round trips for frame callbacks** | Fire-and-forget `cw_present.frame_callback` |
| **No deterministic testing** | Golden frames, protocol replay, CTS |
| **No fuzzing harness** | `tests/fuzz/` per parser |

---

## 4. Key Architectural Decisions Unique to Canvas

### 4.1 Single Address Space + Software Isolation
- **X11/Wayland**: Process isolation (MMU, pid namespaces)
- **Canvas**: Tattva is ring-0 unikernel → no HW domains yet
- **Solution**: Generation handles + per-client arenas + bounded SPSC rings + RSO verifier
- **Trade-off**: Only as strong as verifier; no untrusted binaries until HW domains

### 4.2 No Event Loop Abstraction (libwayland, libxcb)
- **Canvas**: Hand-written event loop in `loop.asm` — single `tv_wait_wait` on IRQ + channels + timers
- **Why**: Zero overhead, predictable latency, no callback hell

### 4.3 Protocol as Source of Truth (cwpgen)
- **Wayland**: XML → C headers (wayland-scanner)
- **Canvas**: `.cwp` IDL → NASM dispatch tables, client stubs, docs, fuzz harness
- **Benefit**: One definition, no drift, mechanical code generation

### 4.4 Renderer/Backend Separation
- **Wayland**: Compositor = renderer + backend (Weston, Mutter, KWin, Sway all differ)
- **Canvas**: `render_iface.asm` + `backend_iface.asm` — swap SW/GPU, headless/native/remote

### 4.5 Policy as Pluggable Module
- **X11**: Separate process (race conditions)
- **Wayland**: Baked into compositor (fragmentation)
- **Canvas**: `policy_iface.asm` — floating/tiling/kiosk built-in, external process via `cw_policy`

### 4.6 Deterministic Replay
- **Neither has this** — Canvas records full protocol + input + timers → replays frame-perfect

### 4.7 Conformance Suite Ships with Server
- **Neither has this** — `tests/cts/` runs on any Canvas build or client

---

## 5. Protocol Design: CWP vs Wayland Wire Format

| Aspect | Wayland | Canvas (CWP) |
|--------|---------|--------------|
| **Header** | 8 bytes (sender_id, opcode, size) | 12 bytes (obj, opcode, flags, len) |
| **Alignment** | 4-byte | 4-byte |
| **Object IDs** | 32-bit, no generation | 32-bit = 20b index + 12b generation |
| **Handles in messages** | Embedded (fd passing) | **Separate handle channel** (never in payload) |
| **Versioning** | Per-interface, bind-time | Per-interface, negotiate at connect |
| **Events vs Requests** | Same wire format | `flags: IS_EVENT` bit |
| **Errors** | Per-object, disconnects client | Per-client error object, disconnect only that client |
| **Flow control** | None (unbounded) | Bounded rings, throttle → disconnect |
| **Extensions** | New interfaces | Capability-gated interfaces |

---

## 6. Performance Philosophy

| X11/Wayland Reality | Canvas Target |
|---------------------|---------------|
| "Good enough" latency | **Input→photon in 1 vblank** (direct scanout) |
| "Reasonable" memory | **< 8 MB server resident** (no client buffers) |
| "Acceptable" startup | **< 100 ms cold start to first frame** |
| Compositor-dependent | **Measured targets at C32** on your hardware |
| No idle optimization | **Zero wakeups when idle** (no damage, no timers) |

---

## 7. What Canvas Cannot Do (Yet) — Honest Gaps

| Gap | X11/Wayland Status | Canvas Mitigation |
|-----|-------------------|-------------------|
| **GPU driver coverage** | Mature (amdgpu, i915, nvidia) | One family at a time (C24); SW renderer + direct scanout first |
| **App ecosystem** | Everything runs | Client lib + reference clients; Utkarsha browser later |
| **Hardware isolation** | Process + MMU | Software isolation only; HW domains when Tattva adds paging |
| **Video decode** | VA-API, VDPAU, DMABUF import | Out of scope (C16: only protocol hooks) |
| **3D APIs (GL/Vulkan)** | EGL/GBM/Vulkan WSI | Out of scope — browser gets own plan |
| **Mature IME engines** | ibus, fcitx, maliit | Protocol only (`cw_text`); engine is client |
| **Screen readers** | Orca, NVDA | Hooks only (`cw_a11y`); reader is client |
| **Multi-GPU (PRIME, muxless)** | Complex but works | Single GPU family; multi-GPU later |

---

## 8. Decision Records Referenced

| # | Title | Relevance |
|---|-------|-----------|
| 0001 | No libc | Avoids X11/Wayland dependency on C runtime |
| 0002 | Pixel format | Avoids X11 visual/colormap mess |
| 0003 | Wire protocol shape | Avoids Wayland registry round-trips, fd passing |
| 0004 | Generation handles | Solves X11 resource leak / Wayland use-after-free |
| 0005 | One server, pluggable policy | Avoids X11 WM race, Wayland fragmentation |
| 0006 | Explicit sync in v1 | Avoids Wayland's late explicit sync adoption |
| 0007 | Trust profiles | Avoids X11 no-security, Wayland ad-hoc extensions |
| 0008 | Software isolation | Tattva constraint, not choice |
| 0009 | Driver boundary | Tattva owns buses, Canvas owns display engines |
| 0010 | First display/GPU family | Scope control — one at a time |

---

## 9. Summary: Canvas Positioning

```
                          Performance
                              ▲
                              │
                    ┌─────────┴─────────┐
                    │                   │
              Wayland              Canvas
              (compositor-          (bare metal,
               dependent)           measured)
                    │                   │
                    ▼                   ▼
              Security             Security
              (compositor-         (capability-
               dependent)           based, v1)
                    │                   │
                    ▼                   ▼
              Ecosystem            Ecosystem
              (mature)             (building)
```

**Canvas is not "X11 but faster" or "Wayland but simpler".** It is a **display server designed for a bare-metal unikernel OS** with explicit sync, capability security, pluggable policy, and deterministic observability — things X11 never had and Wayland added piecemeal over a decade.

---

## 10. Living Document

This file records **why** decisions were made. When a decision changes:
1. Update `architecture.md` or `proto/*.cwp`
2. Add entry to `docs/decisions/NNNN-short-name.md`
3. Reference it here

The goal: future maintainers (or you in 6 months) understand the *reasoning*, not just the *result*.
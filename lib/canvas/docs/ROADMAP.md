# Canvas Roadmap

**Display server for Utkarsha OS: everything planned from here on.**

`PLAN.md` describes how the original codebase was laid out (phases C0–C33). This document is the forward plan. It lists every capability Canvas should eventually have, grouped by area, with each item assigned to a phase. The starting point is the state recorded on 2026-10-22: every module assembles and the server image links, but nothing is wired into the event loop yet.

---

## How to read this

**IDs** are `AREA-NN`, for example `CMP-07`. Use them in commits, issues and decision records.

**Phase** says when an item is due:

| Phase | Name | Goal | Exit criteria |
|---|---|---|---|
| **P0** | Foundation | One consistent, buildable, testable codebase | All build and test images link; one source for struct layouts; unit tests run on the host shim and pass |
| **P1** | Integration | One client renders one frame through the complete path | Client connects, creates buffer and surface, commits; server composites to `headless` (golden checksum) and then to `fb_linear` on hardware |
| **P2** | Core Release (1.0) | A functional desktop suitable for daily use | Input routed to focused windows, floating shell, text on screen, clipboard, lock screen, trust profiles enforced, basic accessibility |
| **P3** | Production Hardening (1.x) | Refinement, performance and resilience | Meets the quality requirements below; GPU composition on the first family; HDR and color correct; survives a 30-day soak |
| **P4** | Extended Capabilities (2.0) | Remote display, managed deployment, real-time and media-production workloads, broader hardware support | Per-area exit criteria set when the phase opens |
| **P5** | Future Work | New form factors and research topics | Re-evaluated every release |

**Notes column:**
- ◐ means partial code already exists. The note says where; "orphan" means the file is in the tree but not in the Makefile.
- → names the main dependency.

**Quality requirements**, which every item in P3 or later must meet:
- **Latency:** input to photon in one frame or better.
- **Smoothness:** zero dropped frames during animation on reference hardware.
- **Resilience:** no session loss short of power loss.
- **Security:** a hostile client cannot see, steal, inject or stall.
- **Proof:** every claim is backed by a benchmark or test in CI.

---

## Areas

1. [Foundation and build](#fnd--foundation-and-build) (FND)
2. [Kernel contract and system integration](#krn--kernel-contract-and-system-integration) (KRN)
3. [Server core and internals](#srv--server-core-and-internals) (SRV)
4. [Reliability and resilience](#rel--reliability-and-resilience) (REL)
5. [Protocol and client API](#pro--protocol-and-client-api) (PRO)
6. [Surfaces and buffers](#sur--surfaces-and-buffers) (SUR)
7. [Compositor and rendering](#cmp--compositor-and-rendering) (CMP)
8. [2D graphics engine](#g2d--2d-graphics-engine) (G2D)
9. [GPU](#gpu--gpu) (GPU)
10. [Display and output](#out--display-and-output) (OUT)
11. [Color](#col--color) (COL)
12. [Input: keyboard](#key--input-keyboard) (KEY)
13. [Input: pointer and cursor](#ptr--input-pointer-and-cursor) (PTR)
14. [Input: touch, pen and other devices](#tch--input-touch-pen-and-other-devices) (TCH)
15. [Text and fonts](#txt--text-and-fonts) (TXT)
16. [Text input and IME](#ime--text-input-and-ime) (IME)
17. [Windows, workspaces and policy](#win--windows-workspaces-and-policy) (WIN)
18. [Desktop components](#dsk--desktop-components) (DSK)
19. [Theming and design system](#thm--theming-and-design-system) (THM)
20. [Interaction design and feedback](#ixd--interaction-design-and-feedback) (IXD)
21. [Data transfer](#dat--data-transfer) (DAT)
22. [Images and media](#med--images-and-media) (MED)
23. [Capture, remote and casting](#rem--capture-remote-and-casting) (REM)
24. [Accessibility](#a11y--accessibility) (A11Y)
25. [Security and privacy](#sec--security-and-privacy) (SEC)
26. [Sessions, power and sensors](#ses--sessions-power-and-sensors) (SES)
27. [Governance and resource control](#gov--governance-and-resource-control) (GOV)
28. [Managed deployment and compliance](#mgd--managed-deployment-and-compliance) (MGD)
29. [Internationalization](#i18n--internationalization) (I18N)
30. [Real-time interactive applications](#rta--real-time-interactive-applications) (RTA)
31. [Media production and color-critical work](#mpr--media-production-and-color-critical-work) (MPR)
32. [Form factors](#frm--form-factors) (FRM)
33. [On-device intelligence](#ai--on-device-intelligence) (AI)
34. [Automation and extensibility](#ext--automation-and-extensibility) (EXT)
35. [Observability](#obs--observability) (OBS)
36. [Performance engineering](#prf--performance-engineering) (PRF)
37. [Testing and quality](#qa--testing-and-quality) (QA)
38. [Developer experience and SDK](#dev--developer-experience-and-sdk) (DEV)
39. [Release and lifecycle](#lif--release-and-lifecycle) (LIF)
40. [Docs, ecosystem and process](#eco--docs-ecosystem-and-process) (ECO)

---

## FND — Foundation and build

| ID | Item | Phase | Notes |
|---|---|---|---|
| FND-01 | Single source of truth for struct layouts: one `struc` per object; delete all local offset `%define`s | P0 | 52 conflicting offsets in 111 files today |
| FND-02 | Build check that fails on duplicate or conflicting struct offsets | P0 | → FND-01 |
| FND-03 | Extern/global consistency: each module header declares its exports; nothing redefines a global | P0 | |
| FND-04 | Fix test and mock symbol collisions so all test images link | P0 | |
| FND-05 | Makefile: `all` without `test`; no duplicate `linker.ld`; add `GFX_SRCS` to the replay image; one owner for `linker.ld` | P0 | |
| FND-06 | Release build mode (`DEBUG_BUILD=0`), warnings as errors | P0 | |
| FND-07 | Move the 31 non-assembling orphan files to an attic; decide wire-in or attic for the other unlisted files | P0 | |
| FND-08 | Line-ending policy in `.gitattributes` for `.asm`, `.inc` and `.md` | P0 | |
| FND-09 | Host test shim: `ut_*` implemented over the dev machine so tests run off-target (test builds only) | P0 | |
| FND-10 | `make check` that builds and runs unit, golden and fuzz suites | P0 | → FND-09 |
| FND-11 | Separate text/rodata/data segments in the linker script (W^X images) | P0 | ld warns about RWX segments today |
| FND-12 | Dual-assembler CI: NASM and utasm both green, outputs compared byte for byte | P1 | 12 files currently utasm-only failures |
| FND-13 | Static lint: register-use and ABI conventions, missing `ret`, stack alignment | P2 | |
| FND-14 | Reproducible builds: identical image hashes from identical source | P3 | |
| FND-15 | Binary size budget per subsystem, tracked in CI | P3 | |
| FND-16 | Modular build profiles: minimal (kiosk), standard (desktop), full (workstation) | P3 | |
| FND-17 | Optional features as build flags (decoders, remote, GPU families) | P3 | → FND-16 |
| FND-18 | Rename pass: `.asm`→`.s`, binding prefixes and naming, in step with the rest of the OS | P2 | Coordinate OS-wide |

## KRN — Kernel contract and system integration

| ID | Item | Phase | Notes |
|---|---|---|---|
| KRN-01 | Agree the syscall ABI with the kernel (numbers, registers, return conventions) | P1 | ◐ proposal in `inc/ut.inc`, `utkarsha-contract.md` |
| KRN-02 | Move every config and asset path to the root layout: config in `/conf`, trust in `/sec/trust`, assets under `/app` | P1 | Contract still uses old paths |
| KRN-03 | Channel and shared-memory primitives for client↔server rings | P1 | → KRN-01 |
| KRN-04 | Handle passing between tasks (buffers, fences) | P1 | |
| KRN-05 | IRQ, MMIO, PCI and DMA services for the native backend | P2 | ◐ `ut_platform.asm` wrappers |
| KRN-06 | Input device event delivery from kernel drivers | P2 | ◐ `source_ut.asm` |
| KRN-07 | Early boot splash owned by Canvas, handed off from the firmware framebuffer | P3 | |
| KRN-08 | Flicker-free handoff boot → login → desktop with no mode switch or black frame | P3 | → KRN-07 |
| KRN-09 | Crash screen: kernel or server panic drawn legibly with error code | P3 | |
| KRN-10 | Recovery console surface if the shell fails | P3 | |
| KRN-11 | Encrypted-disk unlock UI before full boot | P4 | |
| KRN-12 | Update progress screen during system updates | P4 | |
| KRN-13 | Shutdown and reboot transition with no garbage frames | P3 | |
| KRN-14 | Audio subsystem hooks: UI sounds, A/V sync timestamps, display-audio routing info | P4 | |

## SRV — Server core and internals

| ID | Item | Phase | Notes |
|---|---|---|---|
| SRV-01 | Wire `canvasd_init`: arena → handle tables → backend → outputs → input → shell | P1 | ◐ all stages empty today |
| SRV-02 | Event loop dispatch for IRQ, channel, timer and input | P1 | ◐ handlers are bare `ret` |
| SRV-03 | Server arena via `core/arena` instead of ad-hoc globals | P1 | |
| SRV-04 | Client accept, registry and teardown | P1 | ◐ `server/client` |
| SRV-05 | Fair round-robin client dispatch per loop iteration | P2 | ◐ `governance/scheduler` |
| SRV-06 | Config loading: server, outputs, seats, policy, rules files | P2 | ◐ `core/config` |
| SRV-07 | Live config reload without restart | P3 | |
| SRV-08 | Slab allocators for hot fixed-size objects (surfaces, regions, events) | P3 | |
| SRV-09 | Lock-free multi-producer queues for input and IO threads | P3 | |
| SRV-10 | Per-output render threads | P3 | |
| SRV-11 | Work-stealing job system for decode, raster and encode | P3 | |
| SRV-12 | Copy-on-write surface state for low-cost atomic commits | P3 | |
| SRV-13 | Spatial index for hit testing (grid / R-tree) for thousands of surfaces | P3 | |
| SRV-14 | Interned strings for app IDs, MIME types and titles | P3 | |
| SRV-15 | Arena compaction for long-lived sessions | P4 | |
| SRV-16 | Generation-handle exhaustion strategy: table rotation, client recycling | P3 | |
| SRV-17 | Object lifetime tracing: who holds what; leak finder | P3 | |
| SRV-18 | Per-frame budget accounting per stage, with alerts on overrun | P3 | |
| SRV-19 | Scale target: 256 clients, 1,000+ surfaces, no O(n²) paths in hit test, z-order or damage | P3 | |

## REL — Reliability and resilience

| ID | Item | Phase | Notes |
|---|---|---|---|
| REL-01 | Bounded-everything audit: every queue, cache and allocation has a hard limit and a test | P2 | |
| REL-02 | Slow client throttled, then disconnected; OOM affects only that client | P2 | ◐ governance |
| REL-03 | Graceful degradation ladder: GPU → SIMD software → scalar software, automatic | P3 | |
| REL-04 | Watchdog-protected render thread: a stuck frame falls back to the last good frame | P3 | |
| REL-05 | Driver fault isolation: display or GPU fault resets the engine, session survives | P3 | |
| REL-06 | Memory pressure handling: evict glyph, texture and thumbnail caches before killing clients | P3 | |
| REL-07 | Scene-graph and handle-table invariants checked every frame in debug builds | P2 | ◐ `obs/invariants.asm` (unlisted) |
| REL-08 | Clock robustness: monotonic time and vblank timestamp sanity, skip and jump handling | P3 | |
| REL-09 | Atomic display-config apply with automatic rollback after timeout | P3 | |
| REL-10 | Safe mode: minimal compositor if config or driver fails | P3 | |
| REL-11 | Server crash-restart with client survival: clients reconnect and resubmit state | P4 | |
| REL-12 | Deterministic replay bug reports: one file reproduces any rendering bug | P3 | ◐ `obs/record`, `obs/replay` |
| REL-13 | Long-uptime stability: 30-day soak, no leaks, generation wraparound tested | P3 | |
| REL-14 | "Not responding" detection with force-quit dialog | P2 | ◐ watchdog ping |
| REL-15 | Frozen-window snapshot: last frame shown greyed while an app hangs | P3 | |
| REL-16 | Off-screen window recovery when a monitor disappears | P2 | |

## PRO — Protocol and client API

| ID | Item | Phase | Notes |
|---|---|---|---|
| PRO-01 | Real `canvas_connect`: channel pair, handshake, capability grant | P1 | ◐ local-only today |
| PRO-02 | `cwpgen`: generate dispatch tables, server stubs and client stubs from `proto/*.cwp` | P1 | ◐ TODO in `tools/cwpgen` |
| PRO-03 | Capability negotiation: interfaces invisible without grant | P2 | ◐ stub in `proto/negotiate` |
| PRO-04 | Error objects and protocol error reporting | P1 | ◐ `proto/errors` |
| PRO-05 | Per-interface versioning with downgrade negotiation | P2 | ◐ `proto/versioning` |
| PRO-06 | Protocol extension registry | P3 | |
| PRO-07 | Runtime introspection: list interfaces and versions | P3 | |
| PRO-08 | Batched requests: many commands per ring message | P3 | |
| PRO-09 | Request pipelining with deferred errors | P3 | |
| PRO-10 | Message priority lanes: input and frame callbacks ahead of bulk data | P3 | |
| PRO-11 | Shared-memory state blocks for no-message updates (cursor, position) | P4 | |
| PRO-12 | Synchronous barrier / round trip, for debugging only | P2 | |
| PRO-13 | Client capability fingerprinting for compatibility shims | P4 | |
| PRO-14 | Protocol compression for remote channels | P4 | |
| PRO-15 | Viewport: crop and scale a buffer to a destination size | P2 | |
| PRO-16 | Fractional-scale protocol for clients | P2 | ◐ `output/scale_fractional` |
| PRO-17 | Content-type hints (video, game, photo) for scheduling and VRR | P3 | |
| PRO-18 | Activation tokens and focus-request protocol | P2 | |
| PRO-19 | Foreign-toplevel management: taskbars can list and control other windows (privileged) | P2 | |
| PRO-20 | Presentation timing feedback with precise timestamps | P2 | ◐ `server/presentation` |
| PRO-21 | Tearing-control protocol | P3 | |
| PRO-22 | Color-management protocol: buffers tagged with color space and HDR metadata | P3 | |
| PRO-23 | Idle-inhibit protocol | P2 | |
| PRO-24 | Client-side decorations supported alongside server-side | P2 | |
| PRO-25 | Protocol freeze v1, deprecation windows, compatibility tests per version | P3 | |
| PRO-26 | Deprecation tracker for old protocol versions | P4 | |

## SUR — Surfaces and buffers

| ID | Item | Phase | Notes |
|---|---|---|---|
| SUR-01 | Surface create, attach, damage, commit with double-buffered state | P1 | ◐ `server/surface`, `server/commit` |
| SUR-02 | Shared-memory buffers with ownership transfer and release | P1 | ◐ `server/buffer` |
| SUR-03 | Fences and timelines on every buffer (explicit sync) | P1 | ◐ `server/fence`, `server/timeline` |
| SUR-04 | Subsurfaces with sync/desync modes | P2 | ◐ `server/subsurface` |
| SUR-05 | Opaque, input and damage regions | P1 | ◐ `server/regions` |
| SUR-06 | Buffer transforms and scale | P2 | ◐ `server/surface_transform` |
| SUR-07 | Frame callbacks | P1 | ◐ `server/frame_clock` |
| SUR-08 | Surface opacity and transforms applied by the server without client re-render | P3 | |
| SUR-09 | Per-surface alpha modifier | P3 | |
| SUR-10 | Single-pixel buffers: solid colors with no memory | P3 | |
| SUR-11 | Occlusion feedback: clients told how much of them is visible | P3 | |
| SUR-12 | Surface suspension: hidden apps told to stop rendering | P3 | |
| SUR-13 | Preferred buffer scale and transform hints per output | P2 | |
| SUR-14 | FIFO presentation queue for video | P3 | |
| SUR-15 | Commit timing: "present at time T" | P3 | |
| SUR-16 | Surface groups: atomic commit across surfaces of different clients | P4 | |
| SUR-17 | Cross-process embedding: one app embeds another's surface (browser tabs, plugins) | P4 | → SUR-16 |
| SUR-18 | Device buffer import via OS handles (camera, decoder, GPU) | P4 | → KRN-04 |
| SUR-19 | Buffer format modifiers: tiled and compressed GPU layouts negotiated per client | P4 | → GPU |
| SUR-20 | Multiple pixel formats: BGRA/BGRX 8-bit, RGB565, 10-bit, FP16, YUV (NV12/P010) | P2 | ◐ `inc/color.inc` |

## CMP — Compositor and rendering

| ID | Item | Phase | Notes |
|---|---|---|---|
| CMP-01 | Damage-driven software composition into the output buffer | P1 | ◐ `render/compositor`, `render/sw_render` |
| CMP-02 | Buffer-age tracking for partial redraws | P2 | ◐ `render/damage_ring` |
| CMP-03 | Composition order: background → scanout → planes → surfaces → decorations → overlays → cursor | P2 | |
| CMP-04 | Complete SIMD blend paths (SSE2, AVX2, AVX-512) with runtime dispatch | P2 | ◐ AVX2/512 "simplified" |
| CMP-05 | Direct scanout for eligible fullscreen surfaces | P2 | ◐ `server/direct_scanout` |
| CMP-06 | Opaque-region exploitation: no blending under opaque areas | P2 | |
| CMP-07 | Occlusion culling: skip fully hidden surfaces | P2 | |
| CMP-08 | Front-to-back rendering with early reject | P3 | |
| CMP-09 | Render caching: unchanged surfaces kept as composed layers | P3 | |
| CMP-10 | Layer tree with explicit compositing layers per window | P3 | |
| CMP-11 | Damage precision: buffer-age aware, region coalescing heuristics | P3 | |
| CMP-12 | Just-in-time frame scheduling before vblank | P3 | |
| CMP-13 | Late latching of cursor and input before scanout | P3 | |
| CMP-14 | Frame pacing guarantees: jitter budget per output | P3 | |
| CMP-15 | Variable-rate composition: only animating regions at full rate | P3 | |
| CMP-16 | Animation compositor thread: animations continue when apps stall | P3 | |
| CMP-17 | Multi-output frame alignment with different refresh rates | P3 | |
| CMP-18 | Scaled mirroring between different resolutions without blur | P3 | ◐ `output/mirror` |
| CMP-19 | Hardware plane assignment optimizer | P3 | → OUT-01 |
| CMP-20 | Zero-copy path client buffer → plane scanout | P3 | → CMP-19 |
| CMP-21 | Sampling quality: bilinear, bicubic, Lanczos; mipmaps for downscaling | P3 | ◐ `render/sw_scale` |
| CMP-22 | Pixel-perfect fractional scaling (snapping rules for 125/150%) | P3 | |
| CMP-23 | Perceptual blending in linear or OKLab space for gradients and shadows | P3 | |
| CMP-24 | Dithering for 10→8-bit and gradient banding | P3 | |
| CMP-25 | Backdrop sampling cache for blur-behind | P3 | → G2D-07 |
| CMP-26 | Surface atlas packing for small surfaces | P3 | |
| CMP-27 | Partial texture uploads (damaged rows only) | P3 | → GPU-02 |
| CMP-28 | Software vs GPU renderer pixel cross-check mode | P3 | |

## G2D — 2D graphics engine

Lives in `lib/ugfx`: `2d/` on the shared `core/` that 3D will also use. Math (vectors, matrices, fixed point, curve evaluation) comes from `lib/umath`.

The complete list of 104 2D components, with state and dependencies, is in [`lib/ugfx/docs/COMPONENTS.md`](../../ugfx/docs/COMPONENTS.md); the rows below are the milestone summary.

| ID | Item | Phase | Notes |
|---|---|---|---|
| G2D-01 | Primitives: fill, blit, line, circle, rect clip | P1 | ◐ `ugfx/core`, `ugfx/2d` (line/circle simplified) |
| G2D-02 | Region math with SIMD band operations | P3 | ◐ `ugfx/core/region` |
| G2D-03 | Vector paths: moves, lines, quadratic and cubic Béziers, arcs, fill rules | P2 | ✓ `ugfx/2d/path`, `shapes`, `flatten`; built into Canvas |
| G2D-04 | Strokes: width, joins, caps, dashes | P2 | ✓ `ugfx/2d/stroke`, `dash` |
| G2D-05 | Gradients: linear, radial, conic | P2 | ✓ `ugfx/2d/paint` (also two-circle radial and image patterns) |
| G2D-06 | Analytic coverage anti-aliasing; optional MSAA | P2 | ✓ `ugfx/core/raster` exact-area coverage, nonzero and even-odd; host-tested |
| G2D-07 | Filters: blur, shadow, color matrix, saturation | P3 | |
| G2D-08 | Rounded rectangles and window shadows | P2 | ◐ rounded rectangles in `ugfx/2d/shapes`; shadows need G2D-07 |
| G2D-09 | Clip stacks and alpha masks | P2 | ✓ `ugfx/core/mask`, context save/restore |
| G2D-10 | Full Porter-Duff and separable blend modes | P3 | |
| G2D-11 | Nine-patch / border-image drawing | P2 | |
| G2D-12 | Display-list API that `lib/web` and toolkits can emit into | P2 | ◐ `ugfx/2d/context` and `ugfx/2d/list`; not yet exposed to clients |
| G2D-13 | Multi-core tile rasterizer for large surfaces | P3 | → SRV-11 |
| G2D-14 | Material effects (frosted glass, vibrancy) with a low-cost fallback | P3 | → G2D-07 |
| G2D-15 | Conflation-free coverage where overlapping contours meet inside a pixel (exact union instead of accumulated winding area) | P4 | → G2D-06 |

## GPU — GPU

| ID | Item | Phase | Notes |
|---|---|---|---|
| GPU-01 | Fix PM4 type-3 header encoding (type in bits 30–31) | P0 | Bug in `gpu/family/gfx9.asm` |
| GPU-02 | GPU compositor: textured quads, blending, damage clipping | P3 | ◐ `render/gpu_*` |
| GPU-03 | Command ring, fences, memory manager on the first family | P3 | ◐ `gpu/*` |
| GPU-04 | GPU hang detection and reset recovery | P3 | |
| GPU-05 | GPU scheduling and preemption across clients | P3 | |
| GPU-06 | Zero-copy GPU memory sharing between processes | P3 | → SUR-18 |
| GPU-07 | Glyph atlas on the GPU with eviction | P3 | |
| GPU-08 | Per-surface color conversion on the GPU | P3 | → COL |
| GPU-09 | Shader intermediate representation and compiler | P4 | Prerequisite for web graphics |
| GPU-10 | Native 3D API surface for clients | P4 | → GPU-09 |
| GPU-11 | Hardware video decode into scanout planes | P4 | |
| GPU-12 | Upscaling and frame-generation hooks | P5 | |
| GPU-13 | Multi-GPU: render on one, scan out on another | P4 | |
| GPU-14 | Additional GPU and display families | P4 | One at a time per decision 0010 |

## OUT — Display and output

| ID | Item | Phase | Notes |
|---|---|---|---|
| OUT-01 | `headless` and `fb_linear` backends wired and tested | P1 | ◐ `backend/*_full.asm` |
| OUT-02 | Native modeset on the first display family | P2 | ◐ `backend/family/amd/dcn` |
| OUT-03 | Vblank IRQ path with accurate timestamps | P2 | ◐ `native_vblank.asm` (unlisted) |
| OUT-04 | Hardware cursor and overlay planes | P2 | ◐ `native_planes.asm` (unlisted) |
| OUT-05 | Hotplug detect and re-layout | P2 | ◐ orphan `native_hotplug` |
| OUT-06 | Full EDID parsing including monitor descriptors; real mode lists | P2 | ◐ modes hard-coded |
| OUT-07 | Multi-monitor layout, extend and mirror | P2 | ◐ `output/*` |
| OUT-08 | Integer and fractional scale, rotation, gamma, DPMS | P2 | ◐ `output/*` |
| OUT-09 | Display configuration persistence per monitor set | P2 | |
| OUT-10 | Seamless hotplug with no flicker or layout disruption | P3 | |
| OUT-11 | VRR with low-framerate compensation | P3 | ◐ `output/vrr` flag |
| OUT-12 | Tearing / async flip mode | P3 | |
| OUT-13 | Refresh-rate matching for video (23.976/24/25/50/60) | P3 | |
| OUT-14 | HDR output signaling and metadata infoframes | P3 | |
| OUT-15 | Mixing SDR UI over HDR video correctly | P3 | → COL |
| OUT-16 | Backlight control: panel PWM and DDC/CI for external monitors | P2 | ◐ `native_ddc` |
| OUT-17 | Night light and color temperature schedule | P3 | |
| OUT-18 | Panel self-refresh and selective updates | P3 | |
| OUT-19 | DisplayPort MST (daisy-chained monitors) | P4 | |
| OUT-20 | Display Stream Compression for 4K/8K high refresh | P4 | |
| OUT-21 | Very large desktops: 8+ monitors, mixed DPI and refresh | P4 | |
| OUT-22 | Monitor quirks database: EDID fixups, broken modes, VRR blacklists | P3 | |
| OUT-23 | Calibrated profiles for known HiDPI laptop panels | P4 | |
| OUT-24 | Local dimming / mini-LED zone control | P4 | |
| OUT-25 | OLED burn-in protection: pixel shift, static-element dimming | P4 | |
| OUT-26 | Overdrive / response-time tuning | P5 | |
| OUT-27 | Use the display's native scaler for low resolutions | P4 | |
| OUT-28 | TV control over CEC: power, input switching | P4 | |
| OUT-29 | Wireless display output (casting to TVs and projectors) | P4 | |

## COL — Color

| ID | Item | Phase | Notes |
|---|---|---|---|
| COL-01 | Exact sRGB transfer curves (replace approximations) | P2 | ◐ `color/srgb` approx |
| COL-02 | ICC v2/v4 matrix + TRC profiles per output | P2 | ◐ `color/icc_parse`, `matrix`, `trc` |
| COL-03 | ICC v4 parametric curves and LUT-based profiles | P3 | |
| COL-04 | Linear-light blending when any surface is linear or HDR | P3 | ◐ `color/blend_linear` |
| COL-05 | HDR (PQ/HLG) → SDR tone mapping, exact curves, quality presets | P3 | ◐ `color/tonemap` approx |
| COL-06 | SDR brightness control while in HDR mode | P3 | |
| COL-07 | Wide gamut output: Display-P3, Rec.2020 | P3 | |
| COL-08 | 3D LUT output calibration | P3 | |
| COL-09 | 10/12-bit color end to end | P3 | |
| COL-10 | Built-in color test patterns | P3 | |
| COL-11 | Hardware calibrator support and calibration UI | P4 | |
| COL-12 | HDR video tone mapping using per-scene metadata | P4 | |

## KEY — Input: keyboard

| ID | Item | Phase | Notes |
|---|---|---|---|
| KEY-01 | Keyboard routed to the focused surface only | P1 | ◐ `input/keyboard`, `input/focus` |
| KEY-02 | Keymap compiler from readable source to binary | P2 | ◐ `input/keymap` |
| KEY-03 | Multiple layout groups and layout switching | P2 | ◐ group 0 only |
| KEY-04 | Compose and dead keys | P2 | ◐ `input/compose` |
| KEY-05 | Key repeat, with per-key-class rates | P2 | |
| KEY-06 | Global shortcuts mediated by the server | P2 | ◐ `text/shortcuts` |
| KEY-07 | Secure attention sequence that apps can never intercept | P2 | |
| KEY-08 | Per-device keymaps | P3 | |
| KEY-09 | Per-window layouts | P3 | |
| KEY-10 | Custom remapping and macros | P3 | |
| KEY-11 | Modifier-only shortcuts (tap a key alone) | P3 | |
| KEY-12 | Chorded and leader-key shortcuts | P4 | |
| KEY-13 | Custom modifier layers | P4 | |
| KEY-14 | Shortcut conflict detection and resolution UI | P3 | |
| KEY-15 | Lock-key indicators on screen | P3 | |
| KEY-16 | Media keys routed to the active player | P3 | |
| KEY-17 | Per-app shortcut overrides | P4 | |

## PTR — Input: pointer and cursor

| ID | Item | Phase | Notes |
|---|---|---|---|
| PTR-01 | Pointer routing via hit test, enter/leave, buttons, axis | P1 | ◐ `input/pointer`, `input/hittest` |
| PTR-02 | Acceleration profiles (flat, adaptive, custom curve) per device | P2 | ◐ `input/accel` |
| PTR-03 | Scroll speed and natural scroll per device | P2 | |
| PTR-04 | High-resolution scroll events | P2 | |
| PTR-05 | Button remapping, left-handed mode, middle-click emulation | P2 | |
| PTR-06 | Grabs for popups and drag operations | P2 | ◐ `input/grab` |
| PTR-07 | Pointer lock and confinement | P2 | ◐ `input/constraints` |
| PTR-08 | Relative pointer motion | P2 | |
| PTR-09 | Pointer warping only with a grant | P2 | |
| PTR-10 | Pointer barriers and edge pressure between monitors | P3 | |
| PTR-11 | Cursor themes at multiple sizes, auto-scaled per DPI | P2 | ◐ `input/cursor_theme` |
| PTR-12 | Hardware cursor always; never lags under load | P3 | → OUT-04 |
| PTR-13 | Animated cursors and smooth shape transitions | P3 | |
| PTR-14 | Hide cursor while typing; show on move | P3 | |
| PTR-15 | Correct cursor brightness in HDR (linear-light) | P3 | |
| PTR-16 | Per-app custom cursors with size and frame limits | P2 | |
| PTR-17 | Predictive pointer and touch extrapolation | P3 | |
| PTR-18 | Raw low-latency path for high polling-rate mice | P4 | |

## TCH — Input: touch, pen and other devices

| ID | Item | Phase | Notes |
|---|---|---|---|
| TCH-01 | Multi-touch slots and surface delivery | P2 | ◐ `input/touch` (reworked) |
| TCH-02 | Touchpad gestures: pinch, swipe, hold, multi-finger tap; configurable | P2 | ◐ `input/gestures` |
| TCH-03 | Touchpad palm rejection and disable-while-typing | P3 | |
| TCH-04 | Touch-to-pointer emulation for clients without touch | P2 | |
| TCH-05 | Long-press → context menu translation | P3 | |
| TCH-06 | Touch target expansion for small controls | P4 | |
| TCH-07 | System edge swipes with app opt-out policy | P3 | |
| TCH-08 | Touch latency compensation per panel | P4 | |
| TCH-09 | Touchscreen calibration | P3 | |
| TCH-10 | Pen: pressure curves, tilt, eraser, pad buttons and rings | P2 | ◐ `input/tablet` |
| TCH-11 | Pen low-latency front-buffer inking with prediction | P4 | |
| TCH-12 | Gamepads: buttons, axes, rumble | P4 | |
| TCH-13 | Haptics / force feedback | P4 | |
| TCH-14 | Input device quirks database | P3 | |
| TCH-15 | Eye tracking and switch-access input | P5 | |

## TXT — Text and fonts

| ID | Item | Phase | Notes |
|---|---|---|---|
| TXT-01 | TrueType loading, cmap, glyf, composites | P1 | ✓ `lib/ufont` sfnt (cmap 4 / 12, simple and composite glyphs, metrics), used for SVG text; the old `font/*` scaffold removed |
| TXT-02 | Scanline anti-aliased rasterization and glyph cache | P1 | ✓ outlines rasterized as lib/ugfx paths; outlines cached per font in `lib/ufont` |
| TXT-03 | Kerning and metrics | P2 | ✓ metrics in `lib/ufont`; kerning through GPOS (or the kern table) when SVG text is shaped |
| TXT-04 | Text shaping: ligatures, contextual forms, mark positioning | P2 | ✓ `lib/ufont` `ufont_shape` (OpenType GSUB / GPOS as HarfBuzz), SVG text shaped in runs |
| TXT-05 | Indic scripts first-class: Devanagari conjuncts, matras, reph | P2 | ✓ the Indic shaper in `lib/ufont` for Devanagari, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam; their Noto faces shipped |
| TXT-06 | Bidirectional text | P2 | |
| TXT-07 | Line breaking and hyphenation | P2 | |
| TXT-08 | Unicode normalization, grapheme clusters, emoji ZWJ sequences | P2 | ◐ `core/utf8` (simplified) |
| TXT-09 | Font discovery and matching (family, weight, style) | P2 | ◐ `lib/ufont` font sets: CSS family lists, generic names and aliases, weight / style; shipped fonts in `lib/ufont/fonts` |
| TXT-10 | Per-script fallback chains | P2 | ◐ `lib/ufont`: Noto Sans for characters a face lacks |
| TXT-11 | OpenType CFF outlines, WOFF/WOFF2, font collections | P3 | |
| TXT-12 | Variable fonts | P3 | |
| TXT-13 | Color emoji (COLR/CPAL, bitmap tables) | P3 | |
| TXT-14 | Hinting, subpixel positioning, LCD filtering | P3 | |
| TXT-15 | Per-display text tuning: gamma, contrast, stem darkening, optical sizing | P3 | |
| TXT-16 | Font features (tabular numbers, small caps) | P3 | |
| TXT-17 | Synthetic bold and italic | P3 | |
| TXT-18 | Underline, strikethrough and selection drawing | P2 | |
| TXT-19 | SDF/MSDF glyphs for scaled and GPU text | P4 | |
| TXT-20 | On-disk font cache for fast startup | P3 | |
| TXT-21 | Per-user font installation and validation | P4 | |
| TXT-22 | CJK vertical text | P4 | |

## IME — Text input and IME

| ID | Item | Phase | Notes |
|---|---|---|---|
| IME-01 | Input-method protocol: preedit, commit, delete-surrounding | P2 | ◐ `text/*` |
| IME-02 | Candidate window placement and styling | P2 | |
| IME-03 | Caret position reporting for IME, magnifier and screen reader | P2 | |
| IME-04 | Surrounding-text protocol | P2 | |
| IME-05 | Autocorrect and prediction hooks | P4 | |
| IME-06 | Emoji picker | P3 | |
| IME-07 | Character map / input by code point | P3 | |
| IME-08 | On-screen keyboard | P3 | |
| IME-09 | Dictation input | P4 | |
| IME-10 | Handwriting recognition for pen | P5 | |

## WIN — Windows, workspaces and policy

| ID | Item | Phase | Notes |
|---|---|---|---|
| WIN-01 | Toplevel, popup and layer roles with configure/ack | P2 | ◐ `shell/*` |
| WIN-02 | Floating policy | P2 | ◐ `policy/policy_floating` |
| WIN-03 | Tiling and kiosk policies | P3 | ◐ `policy/*` |
| WIN-04 | External policy process interface | P3 | ◐ `policy/policy_external` |
| WIN-05 | Server-side decorations | P2 | ◐ `shell/decoration*` |
| WIN-06 | Popup positioning with constraint solving | P2 | ◐ simplified |
| WIN-07 | Interactive move and resize with frame-synced configure | P2 | ◐ `shell/move_resize` |
| WIN-08 | Min/max size and aspect constraints | P2 | |
| WIN-09 | Maximize, minimize, fullscreen and window states | P2 | ◐ `shell/states` |
| WIN-10 | Modal dialogs: stacking, parent attachment, parent follows | P2 | |
| WIN-11 | Transient windows on the correct workspace and monitor | P2 | |
| WIN-12 | Focus-stealing prevention | P2 | |
| WIN-13 | Startup feedback and app activation | P2 | → PRO-18 |
| WIN-14 | Urgency / attention hints | P2 | |
| WIN-15 | Window icons per instance | P2 | |
| WIN-16 | Workspaces: named, dynamic, per-monitor or global | P2 | ◐ `shell/workspace` |
| WIN-17 | Workspace follows its monitor on replug | P3 | |
| WIN-18 | Snapping, edge tiling, quarter tiling | P3 | |
| WIN-19 | Alt-tab switcher with live thumbnails | P3 | |
| WIN-20 | Overview mode: all windows and workspace grid, drag between workspaces | P3 | |
| WIN-21 | Touchpad 1:1 workspace switching | P3 | |
| WIN-22 | Always-on-top, sticky, pinned windows | P3 | |
| WIN-23 | Picture-in-picture windows | P3 | |
| WIN-24 | Window rules engine and rules UI | P3 | ◐ `shell/rules` |
| WIN-25 | Session restore of window positions | P3 | |
| WIN-26 | Window size snapping to cell grids (terminals) | P3 | |
| WIN-27 | Undo for window operations | P4 | |
| WIN-28 | Window groups and tabs | P4 | |
| WIN-29 | Saved layout presets restored with one key | P4 | |
| WIN-30 | Drop-down scratchpad windows | P4 | |
| WIN-31 | Per-window opacity and click-through | P4 | |
| WIN-32 | Window marks and jump-to-mark | P4 | |
| WIN-33 | Modifier+drag move/resize and mouse gestures | P3 | |
| WIN-34 | Hot corners and edge actions | P3 | |
| WIN-35 | Focus mode dimming everything else | P4 | |
| WIN-36 | User-defined tiling layouts through the external policy | P4 | → WIN-04 |

## DSK — Desktop components

| ID | Item | Phase | Notes |
|---|---|---|---|
| DSK-01 | Wallpaper with scaling modes, per monitor and per workspace | P2 | ◐ `clients/wallpaper` |
| DSK-02 | Panel / taskbar with grouping, pinning, badges | P2 | ◐ `clients/panel` |
| DSK-03 | Clock and calendar popup | P2 | |
| DSK-04 | Lock screen | P2 | ◐ `clients/lockscreen`, `session/lock` |
| DSK-05 | Login greeter with user list and accessibility menu | P2 | |
| DSK-06 | Power menu: sleep, restart, shutdown, lock, switch user | P2 | |
| DSK-07 | App launcher with search | P2 | |
| DSK-08 | Volume and brightness on-screen displays | P2 | |
| DSK-09 | Quick settings: brightness, do-not-disturb, scale, night light | P3 | |
| DSK-10 | Battery, network and status indicators | P3 | |
| DSK-11 | Status-item (tray) protocol | P3 | |
| DSK-12 | Notifications: toasts, grouping, actions, inline replies, priorities | P3 | |
| DSK-13 | Notification center with history and search | P3 | |
| DSK-14 | Do-not-disturb schedules and per-app exceptions | P3 | |
| DSK-15 | Notification rate limiting for noisy apps | P3 | |
| DSK-16 | Lock screen widgets, media controls and private notifications | P3 | |
| DSK-17 | Display arrangement editor, identify overlay, test-mode countdown, preview | P2 | |
| DSK-18 | Screenshot tool: region, window, full screen | P2 | → REM-01 |
| DSK-19 | Command palette / global search overlay | P3 | |
| DSK-20 | Clipboard manager UI | P3 | → DAT-07 |
| DSK-21 | Drag-drop holding shelf | P4 | |
| DSK-22 | Screen ruler, color picker, pixel magnifier | P4 | |
| DSK-23 | Desktop icons layer (optional) | P5 | |
| DSK-24 | Media now-playing overlay | P3 | |
| DSK-25 | First-run setup: displays, scaling, accessibility, language | P3 | |

## THM — Theming and design system

| ID | Item | Phase | Notes |
|---|---|---|---|
| THM-01 | Design tokens: spacing, radii, motion, colors, as one source | P2 | |
| THM-02 | Theme engine for server-drawn UI | P2 | ◐ `shell/theme` |
| THM-03 | Dark mode and automatic light/dark switching | P3 | |
| THM-04 | Accent color extracted from wallpaper | P3 | |
| THM-05 | High-contrast variant of every component | P2 | ◐ `a11y/high_contrast` |
| THM-06 | UI density and font scaling settings | P3 | |
| THM-07 | Decoration button layout customization | P3 | |
| THM-08 | Per-app theme override | P4 | |
| THM-09 | Vector icon pipeline and icon theme loader with cache | P2 | ◐ UIC packs (`lib/ugfx`, 33 312 open icons), built-in UI pack in `shell/icons`; theme loader pending |
| THM-10 | Signed theme package format | P4 | |

## IXD — Interaction design and feedback

| ID | Item | Phase | Notes |
|---|---|---|---|
| IXD-01 | Animation framework: easing curves, spring physics | P3 | |
| IXD-02 | Window open/close/minimize transitions | P3 | → IXD-01 |
| IXD-03 | Shared-element / morph transitions | P4 | |
| IXD-04 | Kinetic scrolling and overscroll physics per device | P3 | |
| IXD-05 | Instant wake: first frame on resume under 100 ms | P3 | |
| IXD-06 | Busy indicators that never block input | P2 | |
| IXD-07 | Human-readable error messages for display and permission failures | P2 | |
| IXD-08 | UI sound hooks | P4 | → KRN-14 |
| IXD-09 | Haptic feedback hooks | P4 | |
| IXD-10 | Shortcut cheat-sheet overlay | P3 | |
| IXD-11 | Interactive gesture and shortcut tutorial | P4 | |
| IXD-12 | "What changed" overlay after updates | P4 | |
| IXD-13 | Contextual help hooks in server-drawn UI | P4 | |

## DAT — Data transfer

| ID | Item | Phase | Notes |
|---|---|---|---|
| DAT-01 | Clipboard and primary selection | P2 | ◐ `data/clipboard`, `selection` |
| DAT-02 | Drag and drop with MIME negotiation | P2 | ◐ `data/dnd`, `mime` |
| DAT-03 | Transfer size limits | P2 | ◐ `data/limits` |
| DAT-04 | Rich formats: HTML, rich text, images, file lists, custom types | P2 | |
| DAT-05 | Lazy rendering: data produced only when pasted | P2 | |
| DAT-06 | Streaming of very large transfers without stalls | P3 | ◐ `data/transfer` |
| DAT-07 | Clipboard history with sensitivity flags | P3 | |
| DAT-08 | Drag thumbnails and feedback icons | P3 | |
| DAT-09 | Drag and drop between remote and local sessions | P4 | |
| DAT-10 | Opt-in encrypted clipboard sync across devices | P5 | |

## MED — Images and media

| ID | Item | Phase | Notes |
|---|---|---|---|
| MED-01 | Decoder test coverage for every supported format | P0 | ◐ PNG, JPEG, WebP tests exist |
| MED-02 | Generic `image_decode` with format sniffing | P1 | ◐ `img/sniff` |
| MED-03 | EXIF orientation, embedded ICC, XMP metadata | P2 | |
| MED-04 | Decode-to-scale for JPEG and WebP | P3 | |
| MED-05 | Progressive / streaming decode display | P3 | |
| MED-06 | Decode cancellation and time budgets | P3 | |
| MED-07 | Decoders run under strict quotas (decode sandbox) | P3 | |
| MED-08 | Animated playback scheduler tied to the frame clock (GIF, WebP, APNG) | P3 | ◐ `gif_animation`, `webp_animation` |
| MED-09 | Animated frame cache with memory caps | P3 | |
| MED-10 | APNG decoding | P3 | |
| MED-11 | Image encoders: PNG, QOI, JPEG (screenshots, export) | P2 | |
| MED-12 | Thumbnail service with cache | P3 | |
| MED-13 | Tiled giant-image streaming into surfaces | P4 | |
| MED-14 | AVIF, HEIF, JPEG XL decoding | P5 | Deferred by decision 0011 |
| MED-15 | Video playback path: YUV buffers, conversion, direct plane scanout | P3 | → SUR-20 |
| MED-16 | Audio/video sync via shared presentation timestamps | P4 | → KRN-14 |
| MED-17 | Subtitle and caption rendering service | P4 | |
| MED-18 | Video quality pipeline: deinterlace, scaling filters, sharpening | P4 | |
| MED-19 | Camera preview pipeline | P4 | ◐ `img/camera` (decode only) |

## REM — Capture, remote and casting

| ID | Item | Phase | Notes |
|---|---|---|---|
| REM-01 | Screen capture protocol, privileged and audited | P2 | ◐ capability defined |
| REM-02 | Screen recording | P3 | → REM-07 |
| REM-03 | High-resolution capture (render at 2–4×) | P4 | |
| REM-04 | Export a window or region to PDF/SVG (vector when available) | P4 | |
| REM-05 | Print-preview rendering path | P4 | |
| REM-06 | Instant replay buffer | P4 | |
| REM-07 | Video encoder for remote and recording | P4 | |
| REM-08 | RFB server over TLS with tile diff and compressed encodings | P4 | ◐ `remote/rfb_*` |
| REM-09 | Native remote protocol with adaptive compression | P4 | ◐ `remote/crp_*`, `codec/*` |
| REM-10 | Multi-viewer sharing, read-only or interactive | P4 | ◐ `remote/crp_share` |
| REM-11 | Multiple virtual outputs (headless cloud desktop) | P4 | ◐ `remote/virtual_output` |
| REM-12 | Remote session follows the viewer's window size | P4 | |
| REM-13 | Multi-monitor remote sessions | P4 | |
| REM-14 | Bandwidth-adaptive quality with region-of-interest encoding | P4 | |
| REM-15 | Session survives network drops | P4 | |
| REM-16 | Single-window remote streaming | P4 | |
| REM-17 | Remote clipboard and file transfer | P4 | |
| REM-18 | Remote audio and USB device forwarding hooks | P5 | |
| REM-19 | Remote GPU rendering streamed to thin clients | P5 | |
| REM-20 | Remote latency HUD | P4 | |
| REM-21 | Encrypted remote channels with key pinning and rotation | P4 | |
| REM-22 | Discovery of nearby displays | P5 | |

## A11Y — Accessibility

| ID | Item | Phase | Notes |
|---|---|---|---|
| A11Y-01 | Accessibility tree protocol for clients | P2 | ◐ `a11y/a11y_tree` |
| A11Y-02 | Screen reader bridge and server-event announcements | P2 | ◐ `a11y/a11y_reader_hooks` |
| A11Y-03 | Keyboard-only operation of all server-drawn UI | P2 | |
| A11Y-04 | Sticky keys | P2 | ◐ `a11y/sticky_keys` |
| A11Y-05 | Slow, bounce and mouse keys | P3 | |
| A11Y-06 | Magnifier following focus and caret | P2 | ◐ `a11y/magnifier` |
| A11Y-07 | High-contrast mode | P2 | ◐ `a11y/high_contrast` |
| A11Y-08 | Color filters: color-blind modes, grayscale, inversion | P3 | |
| A11Y-09 | Reduced motion | P3 | → IXD-01 |
| A11Y-10 | Large cursor, cursor highlight, shake-to-find, trails | P3 | |
| A11Y-11 | Visual alerts | P3 | |
| A11Y-12 | Text scaling independent of display scaling | P3 | |
| A11Y-13 | Caption overlay surface | P4 | |
| A11Y-14 | Accessibility audit tool for client trees | P4 | |
| A11Y-15 | Conformance with accessibility guidelines for all server UI | P3 | |

## SEC — Security and privacy

| ID | Item | Phase | Notes |
|---|---|---|---|
| SEC-01 | Generation-checked handles on every dispatch | P1 | ◐ `core/handle` |
| SEC-02 | Trust profiles loaded and enforced | P2 | ◐ `security/trust` |
| SEC-03 | Capability gate with audit entries for privileged interfaces | P2 | ◐ `security/gate`, `audit` |
| SEC-04 | Server-drawn permission prompts that clients cannot spoof | P2 | ◐ `security/prompts` |
| SEC-05 | Capability tokens: entropy-seeded, keyed-hash authenticated, constant-time checks | P2 | ◐ `security/token` |
| SEC-06 | Input validation at every trust boundary (lengths, counts, overflow) | P2 | |
| SEC-07 | Zeroed pages before buffers are reused by another client | P2 | |
| SEC-08 | Secure input mode: password fields hidden from other clients and the IME | P2 | |
| SEC-09 | Privacy indicators for screen, camera and microphone capture | P3 | |
| SEC-10 | Per-app permission management and revocation UI | P3 | |
| SEC-11 | Private window flag: excluded from capture, thumbnails and remote views | P3 | |
| SEC-12 | Overlay / clickjacking protection on prompts | P3 | |
| SEC-13 | Auto-hide notifications while screen sharing | P3 | |
| SEC-14 | Rate-limited error logging | P2 | |
| SEC-15 | Guard pages and canaries around arenas in debug builds | P2 | |
| SEC-16 | Signed image verification at load | P3 | |
| SEC-17 | Side-channel review: hit-test, prompt and clipboard timing | P4 | |
| SEC-18 | Hardware-backed capability tokens | P5 | |
| SEC-19 | Signed protocol logs for forensics | P4 | |
| SEC-20 | Encrypted screen recordings with user-held keys | P5 | |
| SEC-21 | Threat model and attack-surface map | P2 | |
| SEC-22 | Quarterly security review; audit and bug-bounty readiness | P4 | |

## SES — Sessions, power and sensors

| ID | Item | Phase | Notes |
|---|---|---|---|
| SES-01 | User sessions per seat | P2 | ◐ `session/*` |
| SES-02 | Lock, unlock and idle handling | P2 | ◐ `session/lock`, `idle` |
| SES-03 | Suspend/resume with display restore and buffer preservation | P2 | ◐ `session/power` |
| SES-04 | Multi-seat | P4 | ◐ `session/multiseat` |
| SES-05 | Fast user switching | P3 | |
| SES-06 | Guest sessions with ephemeral state | P4 | |
| SES-07 | Per-user display, theme and accessibility settings applied at login | P3 | |
| SES-08 | Lid switch and clamshell mode | P2 | |
| SES-09 | Ambient light → brightness and contrast | P3 | |
| SES-10 | Orientation sensor auto-rotate and lock | P3 | |
| SES-11 | Proximity sensor screen-off | P4 | |
| SES-12 | Presence detection: lock on leave, wake on return | P5 | |
| SES-13 | Energy-aware modes: lower refresh, frame caps on battery | P3 | |
| SES-14 | Thermal throttling hooks | P4 | |
| SES-15 | Split-screen multiple users on one display | P5 | |
| SES-16 | Handoff of a window session to another device or seat | P5 | |
| SES-17 | Screen-time tracking (local only) and break reminders | P4 | |
| SES-18 | Parental controls at shell level | P4 | |

## GOV — Governance and resource control

| ID | Item | Phase | Notes |
|---|---|---|---|
| GOV-01 | Per-client memory, surface and buffer quotas | P2 | ◐ `governance/quota` |
| GOV-02 | Message rate limits | P2 | ◐ `governance/ratelimit` |
| GOV-03 | Ping/pong watchdog | P2 | ◐ `governance/watchdog` |
| GOV-04 | Fault containment per client | P2 | ◐ `governance/containment` |
| GOV-05 | Memory accounting | P2 | ◐ `governance/accounting` |
| GOV-06 | Background-app throttling (frame callbacks slowed when hidden) | P3 | |
| GOV-07 | Per-client GPU time quotas | P3 | → GPU-05 |
| GOV-08 | Per-client bandwidth quotas for capture and remote | P4 | |
| GOV-09 | "App X slowed your system" reports | P4 | |

## MGD — Managed deployment and compliance

| ID | Item | Phase | Notes |
|---|---|---|---|
| MGD-01 | Managed policy: admin-pushed, locked settings, allowed apps | P4 | |
| MGD-02 | Fleet configuration profiles per device class | P4 | |
| MGD-03 | Kiosk and digital signage: locked layout, schedules, remote management | P4 | ◐ `session/kiosk`, kiosk policy |
| MGD-04 | Tamper-evident compliance audit trail | P4 | ◐ `security/audit` |
| MGD-05 | Session shadowing with consent, indicator and logging | P4 | |
| MGD-06 | Data-loss-prevention hooks for clipboard and drag between trust levels | P4 | |
| MGD-07 | Visible or invisible watermarking | P4 | |
| MGD-08 | Lock policies; smartcard, security-key and biometric unlock | P4 | |
| MGD-09 | Single sign-on hooks in the greeter | P4 | |
| MGD-10 | Remote lock and wipe commands | P4 | |
| MGD-11 | Multi-tenant remote hosting | P5 | |
| MGD-12 | Classified-banner and strict-capture profiles | P5 | |
| MGD-13 | Medical grayscale display calibration profiles | P5 | |
| MGD-14 | Health endpoint for fleets | P4 | |
| MGD-15 | Emergency information on the lock screen | P4 | |

## I18N — Internationalization

| ID | Item | Phase | Notes |
|---|---|---|---|
| I18N-01 | Translatable server strings via a message catalog | P2 | |
| I18N-02 | Right-to-left UI mirroring of decorations, panels and layouts | P3 | → TXT-06 |
| I18N-03 | Locale-aware dates, numbers and calendars in shell components | P3 | |
| I18N-04 | Shipped and tested fallback font chains per language | P3 | → TXT-10 |
| I18N-05 | Localization screenshot tests for every shipped language | P4 | |

## RTA — Real-time interactive applications

| ID | Item | Phase | Notes |
|---|---|---|---|
| RTA-01 | Low-latency application mode: effects off, priority up, refresh locked | P4 | |
| RTA-02 | Zero-overhead fullscreen direct-to-plane | P3 | → CMP-05 |
| RTA-03 | Overlay layer for fullscreen applications (FPS, notifications) | P4 | |
| RTA-04 | Per-application display profiles | P4 | |
| RTA-05 | Controller-navigable shell (large-screen mode) | P5 | → TCH-12 |

## MPR — Media production and color-critical work

| ID | Item | Phase | Notes |
|---|---|---|---|
| MPR-01 | Color-critical mode: exact pipeline, no effects, reference white | P4 | → COL |
| MPR-02 | Soft-proofing and gamut warnings | P5 | |
| MPR-03 | Reference monitor support with fixed timings and LUT upload | P5 | |
| MPR-04 | One app spanning multiple displays (video walls, editing suites) | P4 | |
| MPR-05 | Exact presentation timestamps and pull-down cadence for editors | P4 | → SUR-15 |

## FRM — Form factors

| ID | Item | Phase | Notes |
|---|---|---|---|
| FRM-01 | Tablet / convertible mode with touch-friendly layout | P4 | |
| FRM-02 | Foldable and dual-screen layouts; hinge sensors | P5 | |
| FRM-03 | Low-end device profile (1 core, small RAM, SSE2 only) | P3 | |
| FRM-04 | E-ink: partial refresh, ghosting control, grayscale dithering | P5 | |
| FRM-05 | Round and odd-shaped displays | P5 | |
| FRM-06 | Projectors: keystone correction, multi-projector edge blending | P5 | |
| FRM-07 | Large multi-user touch tables | P5 | |
| FRM-08 | Embedded instrument clusters: always-rendered safety layers, fast boot | P5 | |
| FRM-09 | Headset outputs: direct mode, lens distortion, low persistence | P5 | |
| FRM-10 | Stereo 3D output | P5 | |
| FRM-11 | Spatial windows for 3D shells | P5 | → FRM-09 |

## AI — On-device intelligence

All items run on-device, opt-in, behind capability gates.

| ID | Item | Phase | Notes |
|---|---|---|---|
| AI-01 | Live captions overlay | P5 | |
| AI-02 | Screen text recognition: select text in any window or image | P5 | |
| AI-03 | Auto-describe images and unlabeled UI for accessibility | P5 | |
| AI-04 | Region-select visual question to the system assistant | P5 | |
| AI-05 | Window arrangement suggestions | P5 | |
| AI-06 | Learned adaptive brightness and color | P5 | |
| AI-07 | Upscaling for low-resolution apps on HiDPI screens | P5 | |

## EXT — Automation and extensibility

| ID | Item | Phase | Notes |
|---|---|---|---|
| EXT-01 | Scripting interface for windows, workspaces and outputs (capability-gated) | P4 | |
| EXT-02 | Event hooks: on window open, focus, output change | P4 | |
| EXT-03 | Declarative configuration file for the entire desktop | P4 | |
| EXT-04 | Synthetic input for test and automation tools (privileged) | P3 | ◐ inject capability |
| EXT-05 | UI automation through the accessibility tree | P4 | → A11Y-01 |
| EXT-06 | Signed, sandboxed server plugin ABI (effects, layouts) | P5 | |
| EXT-07 | Third-party policy SDK | P4 | → WIN-04 |

## OBS — Observability

| ID | Item | Phase | Notes |
|---|---|---|---|
| OBS-01 | Structured logging: levels, categories, rate limits | P1 | ◐ `core/log` |
| OBS-02 | Trace ring with per-event IDs | P2 | ◐ `obs/trace` |
| OBS-03 | Frame timeline markers | P2 | ◐ `obs/timeline` |
| OBS-04 | Protocol log and record/replay | P2 | ◐ `obs/protolog`, `record`, `replay` |
| OBS-05 | Per-client metrics | P2 | ◐ `obs/metrics`, `stats` |
| OBS-06 | Crash dumps with symbolized reports | P3 | ◐ `obs/faultdump` |
| OBS-07 | Live tracing toggles | P3 | |
| OBS-08 | Debug overlay: damage, FPS, plane usage | P3 | |
| OBS-09 | Per-frame stage breakdown view (CPU, GPU, wait) | P3 | |
| OBS-10 | Dropped-frame cause attribution | P3 | |
| OBS-11 | Input latency histograms per device | P3 | |
| OBS-12 | Arena and buffer memory map viewer | P3 | |
| OBS-13 | Opt-in, aggregate-only, user-controlled field telemetry | P4 | |

## PRF — Performance engineering

| ID | Item | Phase | Notes |
|---|---|---|---|
| PRF-01 | Benchmark harness measuring idle wakeups, latency, compose, memory | P2 | ◐ `tests/bench` (TODO) |
| PRF-02 | Targets from architecture §14 measured on reference hardware | P3 | |
| PRF-03 | Hot-path audit: branchless loops, alignment, prefetch | P3 | |
| PRF-04 | Cache-aware layouts for hot surface lists | P3 | |
| PRF-05 | Core affinity for render, input and IO | P3 | |
| PRF-06 | Startup budget: lazy-loaded decoders, fonts, themes | P3 | |
| PRF-07 | Power profiling: wakeups/s, GPU busy, energy per frame, in CI | P3 | |
| PRF-08 | Per-subsystem performance budgets enforced in CI | P3 | |
| PRF-09 | Published benchmark results per release | P3 | |
| PRF-10 | Photodiode / high-speed camera input-to-photon rig | P4 | |

## QA — Testing and quality

| ID | Item | Phase | Notes |
|---|---|---|---|
| QA-01 | Unit suites green on the host shim | P0 | → FND-09 |
| QA-02 | Golden-image tests with a real corpus | P1 | ◐ harness exists, data empty |
| QA-03 | Continuous fuzzing of every parser: wire, images, fonts, ICC, EDID, keymaps, config | P2 | ◐ `tests/fuzz` |
| QA-04 | Structure-aware wire-protocol fuzzer | P3 | |
| QA-05 | Conformance suite that connects real clients | P2 | ◐ `tests/cts` (TODO) |
| QA-06 | Hostile-client conformance cases | P2 | |
| QA-07 | Soak: churn, hotplug, quota; 24-hour then 30-day | P3 | ◐ `tests/soak` |
| QA-08 | Property-based tests for region math and handle tables | P2 | |
| QA-09 | Differential decoder tests against reference outputs | P2 | |
| QA-10 | Deterministic multi-client race tests | P3 | |
| QA-11 | Simulated vblank clocks for timing tests | P2 | |
| QA-12 | Chaos tests: client kills, hotplugs, memory pressure while rendering | P3 | |
| QA-13 | Long-tail input device tests | P4 | |
| QA-14 | Mutation testing of security checks | P4 | |
| QA-15 | Visual regression across GPU, scale and theme combinations | P4 | |
| QA-16 | Accessibility regression with automated screen reader runs | P4 | |
| QA-17 | Code coverage for assembly (instrumentation or replay) | P3 | |
| QA-18 | Per-commit CI booting the real kernel in an emulator | P2 | → KRN-01 |
| QA-19 | Regression test for every fixed bug | P1 | |
| QA-20 | Hardware compatibility matrix and vendor test kit | P4 | |
| QA-21 | Third-party client certification program | P5 | |

## DEV — Developer experience and SDK

| ID | Item | Phase | Notes |
|---|---|---|---|
| DEV-01 | Stable client library ABI with semantic versioning | P2 | ◐ `client/*` |
| DEV-02 | Client SDK reference docs and tutorials | P2 | ◐ `client-guide.md` stub |
| DEV-03 | Example gallery apps covering every capability | P3 | ◐ `src/clients` |
| DEV-04 | App template generator | P3 | |
| DEV-05 | Simulator mode: run the server in a window on the dev machine | P3 | |
| DEV-06 | Live per-app inspector: surface tree, buffers, damage, timing | P3 | ◐ `canvas_inspect` |
| DEV-07 | Recorded-protocol viewer | P3 | ◐ `canvas_replay` |
| DEV-08 | Golden-image diff viewer | P3 | |
| DEV-09 | Protocol linter | P2 | ◐ `cwplint` placeholder |
| DEV-10 | Admin tools: `canvasctl`, `canvas_info` complete | P2 | ◐ `src/tools` |
| DEV-11 | Widget toolkit on top of the client library | P4 | |
| DEV-12 | Config schema with validation | P2 | |

## LIF — Release and lifecycle

| ID | Item | Phase | Notes |
|---|---|---|---|
| LIF-01 | Release channels: dev, beta, stable | P3 | |
| LIF-02 | Feature flags for staged rollout | P3 | |
| LIF-03 | Config migration between versions | P3 | |
| LIF-04 | Changelog and migration notes per release | P2 | |
| LIF-05 | Separately signed asset packs: fonts, cursors, themes, wallpapers | P3 | |
| LIF-06 | Install-time hardware probing for backend and defaults | P3 | |
| LIF-07 | Live server update with session handoff | P5 | → REL-11 |

## ECO — Docs, ecosystem and process

| ID | Item | Phase | Notes |
|---|---|---|---|
| ECO-01 | Keep `PLAN.md` status column current | P0 | All ☐ today |
| ECO-02 | Docs describe Utkarsha OS on its own terms; old path names removed | P0 | |
| ECO-03 | Admin guide, client guide, protocol reference complete | P3 | ◐ stubs |
| ECO-04 | Decision record for every significant choice | P0 | Ongoing |
| ECO-05 | Definition of done per subsystem: tests, fuzz, docs, benchmark, invariants | P0 | |
| ECO-06 | Owner and review checklist per area | P2 | |
| ECO-07 | Font and asset licensing audit | P3 | |
| ECO-08 | Bug triage and severity policy | P2 | |
| ECO-09 | Performance and security whitepapers backed by data | P4 | |
| ECO-10 | Theme, wallpaper and icon contribution guidelines | P4 | |
| ECO-11 | Usability testing of shell UI | P4 | |
| ECO-12 | Accessibility and privacy regulatory checklists | P4 | |

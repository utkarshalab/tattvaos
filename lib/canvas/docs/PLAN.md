# Canvas: Master Plan

**Canvas** is the display server for **Tattva OS**, written entirely in x86-64 NASM
assembly: no libc, no imports, no third-party code. It owns the screen, turns input
events into focus-routed events, composes windows, and defines the protocol clients
use to draw.

- **Tattva only.** There is no Linux, hosted mode, or other-OS support, and no X11 or
  Wayland compatibility layer. Every design choice assumes bare metal.
- **Display server only.** No browser, toolkit or desktop apps are in this plan. The
  browser gets its own plan later and will be one client of Canvas.

It targets four deployments with one codebase:

- **Desktop / PC** (multi-monitor, HiDPI, input methods, clipboard, drag and drop)
- **Server / headless** (virtual outputs, remote display, many sessions)
- **Kiosk / embedded** (one locked-down app, minimal footprint)
- **Enterprise** (multi-seat, audit, quotas, policy, observability)

Status: **phase C0 of C33 (nothing written yet)**

---

## 1. What "surpass X11 and Wayland" means here

Those are the design benchmarks. Canvas does not run alongside them, so claims are
about design and about absolute measured numbers.

| Dimension | X11 | Wayland | Canvas |
|---|---|---|---|
| Client isolation | clients can generally observe each other's windows and input | isolated by default, but capture and injection are per-compositor extensions | isolation by default; every privileged capability is one gated, audited interface |
| Window-management policy | separate WM process, racy protocol | each compositor reimplements everything | one server, pluggable policy (built-in or out-of-process) |
| Frame correctness | tearing and sync are afterthoughts | good; explicit sync is recent | atomic commits, explicit sync and presentation feedback in v1 |
| Footprint and attack surface | very large, decades of legacy | moderate, depends on libraries | static assembly, no libc, no dependency tree, no OS layers underneath |
| Remote and headless | separate tools | compositor-specific | built-in virtual outputs and TLS-wrapped remote display |
| Observability | limited | compositor-specific | built-in tracing, frame timeline, protocol record and **deterministic replay** |
| Conformance | informal | per-compositor | a conformance suite ships with the server |

**Where Canvas will honestly trail, at least at first:**

| Gap | Why | Mitigation |
|---|---|---|
| GPU and display hardware coverage | every GPU family needs its own driver | software renderer and boot framebuffer first; one hardware family at a time (C10, C24) |
| Application ecosystem | nothing existing runs on Canvas | client library and reference clients; later, native Utkarsha apps (including the browser) |
| Hardware isolation | Tattva clients share one address space (section 3) | software isolation now; hardware domains if Tattva gains them |
| Edge-case maturity | years of bug reports | conformance suite, fuzzing, soak tests, record/replay |

**Measurable targets** (placeholders until baselined at C32, on your hardware):

| Metric | Target |
|---|---|
| Idle CPU | zero wakeups with no damage and no timers |
| Input to photon | next vblank after the event, on a direct-scanout window |
| Server resident memory | under 8 MB idle with 2 outputs (excluding client buffers) |
| `canvasd` image size | under 1 MB |
| Cold start to first frame | under 100 ms after Canvas init |
| Hot-path round trips | none for commit, damage or frame callbacks |
| Scale | 256 clients and 1,000 surfaces without dropped frames (soak test) |

A head-to-head against X11 or Wayland would need Linux on the same machine, so it is
**not part of this plan**. "Surpassing" is claimed only for the dimensions above that
the benchmarks measure.

## 2. Architecture

```
 clients (apps, panel, lock screen, WM policy, remote viewer)
        │  CWP (Canvas Wire Protocol) over in-address-space channels
┌───────▼──────────────────────────────────────────────────────────────┐
│ canvasd                                                              │
│  proto      framing, object table, versioning, capability negotiation│
│  security   trust profiles, capability gate, isolation, audit        │
│  governance quotas, rate limits, watchdog, fault containment         │
│  server     clients, buffers, fences, surfaces, scene graph, commit  │
│  shell      roles, states, configure, workspaces, decorations        │
│  policy     floating, tiling, kiosk, external (cw_policy)            │
│  input      seats, keyboard, pointer, touch, tablet, focus, grabs    │
│  data       clipboard, primary selection, drag and drop              │
│  text/a11y  input methods, accessibility tree, sticky keys           │
│  session    seats, user sessions, lock, idle, kiosk                  │
│  output     layout, modes, scale, rotation, gamma, DPMS, VRR         │
│  color      sRGB baseline, ICC matrix/TRC, HDR metadata              │
│  obs        trace, frame timeline, protocol log, record/replay       │
├──────────────────────────────────────────────────────────────────────┤
│ render      software (SIMD) renderer, direct scanout, planes, GPU    │
│ backend     headless, boot framebuffer, native modeset, remote       │
├──────────────────────────────────────────────────────────────────────┤
│ tattva/     thin binding to Tattva kernel services (inc/tattva.inc)  │
└──────────────────────────────────────────────────────────────────────┘
        Tattva OS (ring 0): memory, timers, interrupts, PCI, input drivers, net, TVFS
        hardware: display controller, GPU, input devices
```

**Support libraries inside the project:** `core` (arenas, strings, maps, rings),
`gfx` (pixels, regions, SIMD blend), `font` (TrueType), `img` (PNG, JPEG, GIF),
`codec` (compression for remote display).

## 3. Isolation on Tattva (decided)

Tattva is a ring-0 unikernel, so Canvas and its clients share one address space. The
plan uses **software isolation**:

1. **Handles only.** Clients never hold raw pointers into server memory. Every object
   is a generation-tagged handle checked on every call.
2. **Channels, not shared state.** Clients talk to Canvas through bounded message
   rings. Bulk pixel data lives in explicit buffers whose ownership transfers on
   attach and release.
3. **Per-client arenas.** Each client has its own memory budget and arena; teardown
   frees everything it owned.
4. **Verified code.** Client code must be built with the Utkarsha toolchain and
   checked by the register-ownership rules (RSO) so it cannot forge handles or touch
   memory it was not given.
5. **Fault containment.** A trap or protocol violation tears down only the offending
   client.

**What this does and does not give you:** isolation is only as strong as the
verifier. Do **not** load untrusted third-party binaries until Tattva has hardware
protection domains (paging, ring 3). Until then, the trust profiles in section 7 mean
"how much of the protocol this verified client may use", not "defence against hostile
machine code". Hardware domains are listed as a future option, not a phase.

## 4. CWP: the Canvas Wire Protocol

**Design rules:**

1. **Binary and versioned.** Header: `object u32, opcode u16, flags u16,
   length u32`. Payload 4-byte aligned. Every interface has a version; both sides
   negotiate down.
2. **Generation-tagged object IDs** so stale IDs can never address a recycled object.
3. **Capability negotiation at connect.** The client asks for capabilities; the
   server grants a subset based on its trust profile.
4. **Atomic state.** Surface state is pending until `commit`. Related changes across
   surfaces can be grouped in a transaction and applied in the same frame.
5. **Explicit sync from day one.** Buffers carry acquire and release fences or
   timeline points.
6. **Presentation feedback.** Every committed frame can report when and how it was
   presented, with a refresh-rate hint.
7. **No round trips on the hot path.** Create, attach, damage, commit and frame
   request are one-way.
8. **Handles ride a separate channel** from payload bytes (buffer and fence handles
   are never embedded in message data).
9. **Errors are per-client.** A protocol violation sends an error object and
   disconnects only that client.
10. **Flow control.** Per-client queues are bounded; a client that cannot keep up is
    throttled, then disconnected, and can never stall the server.
11. **Extensions are interfaces,** each with its own version, negotiated through
    capabilities.
12. **Protocols are defined in `proto/*.cwp`** and compiled by `cwpgen` (written in
    assembly) into dispatch tables, headers and client stubs.

**Interface set (v1):**

| Interface | File | Purpose |
|---|---|---|
| `cw_display`, `cw_caps` | canvas-core | connect, capability negotiation, sync, errors |
| `cw_buffer`, `cw_fence` | canvas-core | buffers and explicit sync |
| `cw_surface`, `cw_subsurface` | canvas-core | surfaces, damage, regions, transforms, scale, commit |
| `cw_present` | canvas-present | frame callbacks, presentation feedback |
| `cw_output` | canvas-output | outputs, modes, scale, rotation, gamma, color, VRR |
| `cw_seat`, `cw_pointer`, `cw_keyboard`, `cw_touch`, `cw_tablet` | canvas-input | input devices and events |
| `cw_shell`, `cw_toplevel`, `cw_popup`, `cw_layer` | canvas-shell | window roles, states, configure, panels, overlays |
| `cw_decoration` | canvas-shell | client or server decorations |
| `cw_data` | canvas-data | clipboard, primary selection, drag and drop |
| `cw_text` | canvas-text | input method and preedit |
| `cw_a11y` | canvas-a11y | accessibility tree and assistive features |
| `cw_session` | canvas-session | lock, idle, inhibit, kiosk |
| `cw_policy` | canvas-policy | out-of-process window manager |
| `cw_capture` | canvas-capture | privileged screen capture |
| `cw_inject` | canvas-inject | privileged input injection and virtual devices |
| `cw_debug` | canvas-debug | privileged inspection and tracing |
| `cw_remote` | canvas-remote | remote display control |

## 5. What Canvas needs from Tattva

Listed precisely in `docs/tattva-contract.md` and `inc/tattva.inc`, so Tattva can grow
exactly these services.

| Service | Used for | Binding file |
|---|---|---|
| Memory regions | arenas, buffers, DMA-able scanout memory | `tv_mem` |
| Monotonic clock and timers | frame clock, key repeat, watchdog | `tv_time` |
| Interrupt registration | vblank, input, channel wakeups | `tv_irq` |
| PCI enumeration and MMIO/DMA | display and GPU drivers | `tv_pci`, `tv_mmio` |
| Task creation and wait/yield | worker tasks, event loop | `tv_task`, `tv_wait` |
| Input event source | keyboard, mouse, touch from Tattva drivers | `tv_input` |
| Console/serial log | logging, test results | `tv_log` |
| Entropy | capability tokens | `tv_entropy` |
| TVFS read | config, fonts, cursors, wallpapers | `tv_fs` |
| Network and TLS | remote display | `tv_net` |
| Power events | suspend and resume | `tv_power` |

**Driver boundary:** Tattva owns buses and generic drivers (PCI, USB host, PS/2, HID
transport). Canvas owns **display** drivers (framebuffer, modeset, planes, EDID, GPU)
and **input interpretation** (keymaps, focus, accel, gestures).

**Boot display:** the first backend uses a linear framebuffer set up by the boot
chain (VBE in the real-mode stage, since the current loader is MBR-based). Native
modeset (C10) replaces it per hardware family.

## 6. Rendering and backends

**Renderer interface** is backend-agnostic: `render_begin(output)`,
`render_surface(...)`, `render_end()`.

- **Software renderer (baseline and reference).** SSE2, AVX2 and AVX-512 paths picked
  at startup by CPU feature detection. Region-based clipping, premultiplied alpha,
  damage-only repaint, buffer-age tracking.
- **Direct scanout.** A single opaque fullscreen client's buffer goes straight to the
  display with no copy.
- **Hardware planes.** Cursor and overlay planes where the display hardware has them.
- **GPU path (C24).** Command ring, blit and fill engines, memory management and
  fences for **one chosen GPU family**, picked from the hardware you actually deploy
  on.

| Backend | Use | Phase |
|---|---|---|
| `headless` | tests and servers with no display; frames kept in memory and dumped on request | C9 |
| `fb_linear` | boot framebuffer (VBE or UEFI GOP), page-flip by copy or double buffer | C9 |
| `native` | PCI display engine programming: modeset, vblank, flip, planes, EDID/DDC, hotplug | C10 |
| `remote` | virtual outputs viewed over remote display | C26 |

## 7. Security model

**Principles:** deny by default, least privilege, every grant explicit and logged.

- **Trust profiles:** `trusted`, `standard`, `sandboxed`, `remote`, `kiosk`, loaded
  from `conf/profiles/`. A client's profile is assigned by whatever launched it.
- **Capability bits** are granted at handshake. Without a capability the interface is
  not even visible to the client.
- **Privileged interfaces** (`cw_capture`, `cw_inject`, `cw_policy`, `cw_debug`,
  `cw_session` lock) need explicit grants and produce audit records.
- **Isolation rules:** a client can never read another client's pixels, observe input
  not routed to it, or inject input, unless granted. Clipboard and drag data pass
  through the server with size and type limits.
- **Focus-gated input:** keyboard and pointer events only go to the focused or
  hit-tested surface. Global shortcuts are server-mediated and registered, not
  snooped.
- **Anti-spoofing:** server-drawn UI (decorations, lock screen, permission prompts) is
  visually distinct and cannot be overlaid by clients.
- **Tokens:** unguessable capability tokens from the CPU entropy source, authenticated
  with a keyed hash.
- **Audit log:** append-only record of grants, privileged calls, client connects and
  disconnects, policy changes.
- **Isolation foundation:** the software-isolation model in section 3.

## 8. Enterprise features

| Feature | Detail |
|---|---|
| Multi-seat | several independent seats, each with its own outputs and input devices |
| Session management | user sessions, lock screen protocol, idle detection, inhibit |
| Kiosk mode | one allowed app, no escape, restart on fault |
| Configuration | text config files (`canvas.conf`, `outputs.conf`, `seats.conf`, `policy.conf`, `rules.conf`) with validation and reload |
| Governance | memory, surface and rate quotas per client; fair scheduling; unresponsive-client detection |
| Observability | trace, frame timeline, per-client stats, metrics, protocol record and replay |
| Remote | TLS-wrapped RFB (no legacy VNC authentication), native compressed remote protocol, view-only sharing |
| Control | `canvasctl` for inspection and control at runtime |
| Conformance | `cts/` suite that any Canvas build or client can be run against |

## 9. Core structures (draft)

- **Handle** (`u32`): 20-bit index, 12-bit generation. Used for every object.
- **Arena** (16 bytes): `base, cursor`. Per-client and per-frame arenas.
- **Ring buffer:** power-of-two, single-producer single-consumer; message queues and
  channels.
- **Message header** (12 bytes): `object u32, opcode u16, flags u16, length u32`.
- **Region:** sorted band list of rectangles with union, intersect, subtract.
- **Buffer:** `handle, w, h, stride, format, base, acquire_fence, release_fence,
  state`.
- **Surface state** (double-buffered): `buffer, offset, damage region, opaque region,
  input region, transform, scale, subsurface tree, frame callbacks`.
- **Output:** `id, name, modes, current mode, position, scale, rotation, gamma LUT,
  color profile, vrr`.
- **Event** (24 bytes): `type u32, time u64, a u32, b u32, c u32`.
- **Client:** `id, trust profile, caps, arena, object table, send queue, quota
  counters, last-ping time`.

Pixel format: **32-bit BGRX/BGRA**, little-endian, premultiplied alpha. Other formats
are negotiated per buffer.

## 10. Client interface (sketch)

```
canvas_connect(caps_wanted)               -> conn
canvas_surface_create(conn)               -> surface
canvas_buffer_create(conn, w, h, fmt)     -> buffer
canvas_surface_attach(surface, buffer, x, y)
canvas_surface_damage(surface, x, y, w, h)
canvas_surface_commit(surface)
canvas_frame_request(surface, callback)
canvas_toplevel_create(surface) / set_title / set_state
canvas_event_poll(conn, out_event)
canvas_clipboard_set(conn, mime, ptr, len)
canvas_disconnect(conn)
```

## 11. Phase table

Legend: `☐` planned, `◐` in progress, `✓` shipped. Sizes are **rough estimates** of
assembly lines and will be replaced by real counts.

### Track A: Foundation

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C0 | Build + Tattva binding | build files; `inc/tattva.inc` contract; `tv_mem`, `tv_time`, `tv_log`, `tv_entropy`, `tv_wait`; stubs for the rest | 1k | ☐ |
| C1 | Core library | arena, str, utf8, hash, siphash, map, vec, ring, handle table, list, rbtree, bitset, fixed, fmt, config parser, logger, cpuid | 3k | ☐ |
| C2 | Graphics primitives | pixbuf, rect, **region**, fill, blit, blend (scalar + SSE2/AVX2/AVX-512), scale, transform, clip, color, PPM/PNG writers, bitmap font | 3.5k | ☐ |
| C3 | Test harness on Tattva | test macros, serial result reporting, headless harness, golden compare by checksum with dump-on-fail, fuzz driver skeleton | 0.8k | ☐ |

### Track B: Protocol

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C4 | CWP codec + `cwpgen` | wire framing, object table, versioning, capability negotiation, error object, IDL compiler for `proto/*.cwp` | 3k | ☐ |
| C5 | Connections | channels (message rings), accept, handshake, client registry, per-client arenas and queues, teardown | 2.5k | ☐ |
| C6 | Buffers + sync | buffers with ownership transfer, formats, release semantics, fences, timelines | 2.5k | ☐ |

### Track C: Server core

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C7 | Scene graph | surfaces, subsurfaces, atomic commit, damage, opaque/input regions, z-order, transforms, scale | 5k | ☐ |
| C8 | Software compositor | damage-driven composition, SIMD blend, buffer age, frame callbacks, presentation feedback, direct scanout | 4.5k | ☐ |
| C9 | Backends I | `headless` and `fb_linear` (boot framebuffer) | 1.5k | ☐ |
| C10 | Backends II: native modeset | PCI discovery, display engine programming for the first chosen family, vblank interrupts, flip, planes, EDID/DDC, hotplug | 8k | ☐ |
| C11 | Output management | multi-monitor layout, mirror/extend, integer and fractional scale, rotation, gamma, DPMS, VRR flag | 4k | ☐ |
| C12 | Input | input sources from Tattva, seats, keymap compiler, compose and dead keys, repeat, pointer accel, constraints, touch, gestures, tablet, focus, grabs, hit-test, cursor | 7k | ☐ |
| C13 | Shell + policy | roles, configure/ack, states, move/resize, workspaces, built-in floating and tiling, external policy interface | 7k | ☐ |
| C14 | Decorations + cursors | server-side decorations, theme engine, cursor themes (needs C21, C22) | 3k | ☐ |
| C15 | Data | clipboard, primary selection, drag and drop, MIME negotiation, limits | 3k | ☐ |
| C16 | Text, a11y, shortcuts | input method protocol, accessibility tree, sticky keys, magnifier, high contrast, global shortcuts, idle inhibit | 4k | ☐ |

### Track D: Security and enterprise

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C17 | Security | trust profiles, capability gate, isolation checks, verifier hooks, tokens, audit log, permission prompts | 4k | ☐ |
| C18 | Sessions + seats | multi-seat, user sessions, lock screen, idle, kiosk, power events | 3k | ☐ |
| C19 | Governance | quotas, rate limits, watchdog, fault containment, fair scheduling, memory accounting | 3k | ☐ |
| C20 | Observability | trace, frame timeline, protocol log, **record and replay**, metrics, debug interface, fault dump | 5k | ☐ |

### Track E: Media and rendering

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C21 | PNG | inflate, zlib, CRC, PNG decode, scaling (cursors, wallpaper, icons) | 1.5k | ☐ |
| C22 | TrueType | cmap, glyf, composites, Bezier flatten, supersampled AA, glyph cache, kerning | 4k | ☐ |
| C23 | JPEG, GIF, BMP, SVG subset | baseline and progressive JPEG, GIF first frame, BMP, simple SVG | 4k | ☐ |
| C24 | GPU acceleration | one GPU family: command ring, blit/fill, memory manager, fences, scanout planes | 15k | ☐ |
| C25 | Color management | sRGB baseline, ICC matrix/TRC, per-output transforms, HDR metadata, linear-light blending | 3k | ☐ |

### Track F: Remote display

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C26 | Remote display I | virtual outputs, TLS-wrapped RFB server, tile diff, compressed encodings, input and clipboard forwarding | 6k | ☐ |
| C27 | Remote display II | native remote protocol, adaptive compression, multi-viewer sharing | 6k | ☐ |

### Track G: Client SDK and tools

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C28 | Client library | connect, objects, buffer pools, double buffering, event loop, helpers | 4k | ☐ |
| C29 | Reference clients | demo windows, alpha and subsurface demos, input/clipboard/DnD/IME tests, panel, wallpaper, lock screen, benchmarks, stress | 3k | ☐ |
| C30 | Tools | `canvasctl`, `canvas-info`, `canvas-record`, `canvas-replay`, `canvas-bench`, `canvas-inspect`, `cwplint` | 4k | ☐ |

### Track H: Hardening and release

| # | Phase | Deliverable | Est. lines | Status |
|---|---|---|---|---|
| C31 | Hardening | fuzz every parser, scene-graph invariants, 24-hour soak, fault injection | n/a | ☐ |
| C32 | Benchmarks | measure every target in section 1 on your hardware, tune, record results | n/a | ☐ |
| C33 | v1.0 release | protocol freeze, conformance suite, documentation, admin and client guides | 5k | ☐ |

**Rough totals (estimates):** about 135k lines of assembly in all.

- **Tier 1, usable desktop server** (C0 to C16, C21, C22, C28 to C30): about 80k
- **Tier 2, enterprise** (C17 to C20, C23, C25): about 22k more
- **Tier 3, reach** (C24, C26, C27, C33): about 33k more

## 12. Milestones

| # | Name | After | What you can see |
|---|---|---|---|
| CM1 | Hello pixel | C3 | a headless frame with shapes and bitmap text, checked on serial |
| CM2 | First client | C8 | one client draws through CWP into the headless backend |
| CM3 | Real screen | C12 | multiple clients on the boot framebuffer with keyboard and mouse |
| CM4 | Usable desktop | C16 | windows, outputs, clipboard, decorations, panel, input methods |
| CM5 | Enterprise | C20 | security profiles, sessions, quotas, tracing, record/replay |
| CM6 | Native display | C10, C24 | native modeset and GPU-accelerated composition on your target hardware |
| CM7 | Remote | C27 | the desktop viewed over TLS-wrapped remote display |
| CM8 | v1.0 | C33 | conformance suite passes, targets measured |

## 13. Order of work

1. C0 to C3 (CM1)
2. C4 to C8 (CM2)
3. C9, C12 (CM3), then C11, C13, C15, C21, C22, C14, C16 (CM4)
4. C28 to C30 alongside C13 onward, so every feature has a client and a tool
5. C17 to C20 (CM5)
6. C10 as soon as the target display hardware is chosen, then C24 (CM6)
7. C26, C27 (CM7)
8. C23, C25 as needs allow
9. C31 to C33 (CM8)

## 14. Testing and conformance

All tests run **on Tattva**, report over serial or console, and use the headless
backend for anything visual.

1. **Unit tests** per module. Pure-logic modules (core, gfx, region, wire codec,
   keymap, config) never touch hardware and can be tested in isolation.
2. **Golden frames:** deterministic scenes rendered by the headless backend and
   compared by checksum; a mismatch dumps the frame for inspection.
3. **Replay tests:** recorded protocol sessions (`tests/replays/`) replayed against
   the server must produce identical frames and events.
4. **Conformance suite (`tests/cts/`):** black-box protocol tests any Canvas build or
   client can run.
5. **Fuzzing:** wire parser, object model, keymaps, config, PNG/JPEG/GIF/TTF, ICC, RFB.
6. **Scene-graph invariants** checked after every commit in debug builds.
7. **Soak tests:** 24-hour runs with churning clients, hotplug and quota pressure.
8. **Benchmarks (`tests/bench/`):** latency, throughput, idle cost, memory.
9. A bug fix lands with a test (or a replay) that fails without it.

## 15. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Scope (about 135k lines) | multi-year effort | tiers; every milestone is shippable; later tiers are optional |
| Native display and GPU drivers | hardware-specific, very large | boot framebuffer and software renderer first; one family only; direct scanout and planes recover much of the benefit |
| Software isolation (section 3) | only as strong as the verifier | handles-only API, per-client arenas, verified clients only; no untrusted binaries until hardware domains exist |
| Tattva service gaps | Canvas blocked on missing OS features | `tattva-contract.md` defines exactly what is needed; stub each service until Tattva provides it |
| No existing apps | nothing to show | reference clients and the later browser; client library kept small and stable |
| Protocol design mistakes | costly to change after freeze | freeze only at C33; `cwplint`, versioning and the conformance suite from early on |
| Bare-metal debugging | slow iteration | headless backend, serial logging, record/replay |
| Solo bandwidth | stalls | generate mechanical code (stubs, tables) with `cwpgen`; small, independently testable modules |
| Memory-safety bugs in assembly | exploitable | bounds-checked wire parsing, per-client arenas, fuzzing, RSO ownership rules |

## 16. Out of scope

Linux or any other OS, hosted mode, X11 and Wayland compatibility, a C ABI,
the browser, 3D APIs (OpenGL, Vulkan), video decode, audio, a GUI toolkit, window
animations and effects, printing, Bluetooth and network management, full IME engines
(only the protocol), screen readers themselves (only the hooks).

## 17. Definition of done (per phase)

- Assembles with no warnings and links into the Tattva image.
- Unit, golden and (where relevant) replay and conformance tests pass on Tattva.
- Status table updated with the real line count.
- Relevant doc in `docs/` written or updated, including a decision record if a
  design choice was made.

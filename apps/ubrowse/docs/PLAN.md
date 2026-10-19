# ubrowse: Master Plan v2, built to compete

A **full-platform web browser** written entirely in x86-64 NASM assembly for
**Tattva OS**, drawing through the **Canvas** display server. The goal is not a niche
privacy tool. It is a browser that competes head-on with Chrome, Firefox and Safari on
**compatibility, speed, security and features**, and beats them on **privacy, footprint
and transparency**.

**One standalone browser, many features.** ubrowse is a normal everyday browser by
default. Two things are built in natively, with no add-ons:

- **Tor switch:** Tor is off by default. Turn it on for a window or a container and
  that traffic goes over Tor; turn it off and you are back to normal browsing
  (section 4.2).
- **Multi-account containers:** colour-coded containers (Personal, Work, Banking,
  Shopping and your own) keep cookies, storage and logins apart, so one browser holds
  several accounts on the same site (section 4.1).

The product is **ubrowse** and lives in `apps/ubrowse/`. It is assembled from
libraries, not built as one block: the rendering engine is **`lib/web/`**, the Tor
client is **`unet/anon/tor/`**, HTTP is `unet/http/`, crypto is `crypto/`. ubrowse
wires them together (section 5.1).

Status: **phase B0 of B91 (nothing written yet)**

This version replaces the earlier privacy-core plan. Its privacy work lives on as the
Private and Tor modes, so nothing already designed is lost.

---

## 1. Positioning: what "best of the best" means

> Chrome-class compatibility and speed, Tor-class privacy, hardware-sandboxed
> security, and a fraction of the memory and attack surface.

| Pillar | The claim to earn | How it is judged |
|---|---|---|
| **Compatibility** | the sites people use every day just work | top-site corpus, Web Platform Tests, test262 |
| **Speed** | feels at least as fast as the leaders | standard JS and rendering benchmarks, page load, startup |
| **Security** | stronger isolation than mainstream defaults | site-per-process hardware sandbox, fuzz coverage, external audits |
| **Privacy** | the most private mainstream-capable browser | leak harness, fingerprint suite, Tor mode |
| **Footprint** | much lighter than the leaders | memory per tab, binary size, startup, battery |
| **Features** | nothing a daily user misses | feature checklist (section 11) |

Nothing is "better" until the scoreboard (section 2) says so. Claims are published
only with measurements.

## 2. The scoreboard

Every release must hit its targets before the next release starts. Targets are
**placeholders to be calibrated at the first measurement** on your hardware.

| Metric | R1 | R2 | R3 | R4 | v1.0 (R5) |
|---|---|---|---|---|---|
| Top-1000 site corpus renders correctly | 30% (static, text-first) | 70% | 75% | 90% | 95%+ |
| Web Platform Tests pass rate in supported areas | n/a | 70% | 75% | 85% | 90%+ |
| test262 (ES2020 and later) | n/a | 80% | 85% | 90% | 95%+ |
| JS speed vs a leading browser on the same hardware | n/a | 25% (interpreter) | 60% (baseline JIT) | 80% (optimizing JIT) | 90%+ |
| Page load, typical top site | within 3x | within 2x | within 1.3x | at parity | at parity or better |
| Cold start to usable window | < 500 ms | < 400 ms | < 300 ms | < 300 ms | < 250 ms |
| Memory per typical tab | < 60% of a leader | < 60% | < 50% | < 50% | < 50% |
| Site isolation and hardware sandbox | tab tasks per container and site (software) | tab tasks | **process per site, hardware sandbox** | same | same, externally audited |
| Leak harness (Tor switch, containers) | green | green | green | green | green |
| Fingerprint suite in Tor mode | measured | within target | within target | within target | parity with Tor Browser vectors |
| Known critical security issues | 0 | 0 | 0 | 0 | 0 plus bug bounty live |

JS speed is the most speculative row. An interpreter is typically many times slower
than a JIT on compute-heavy code, which is why R3 exists.

## 3. Honest scale assessment

Chrome and Firefox are each **tens of millions of lines** built over 15+ years by
hundreds of engineers. Independent engines (for example Ladybird and Servo) show the
order of magnitude: years of work and many contributors, for a fraction of the
platform.

**Phase estimates in this plan sum to about 1.6 million lines of assembly.** Treat
that as a **lower bound**: spec-faithful implementations commonly come out 2 to 3
times larger than first estimates, so plan for **2 to 3 million lines**.

| Release | Scope | Est. lines (lower bound) |
|---|---|---|
| R1 Everyday core | network, static-web rendering, shell, containers, privacy engine, Tor switch | 145k |
| R2 Modern web | JS, flex/grid, workers, storage, components, modern CSS, HTTP/3 | 340k |
| R3 Fast and hardened | process model, hardware sandbox, JITs, GPU raster | 300k |
| R4 Full platform | media, WebAssembly, WebGL/WebGPU, service workers, WebRTC, PDF, extensions, devtools | 680k |
| R5 Product and ecosystem | profiles, sync, passkeys, enterprise, updates | 105k |

**The levers that make this feasible (they reduce risk, they do not remove the scale):**

| Lever | What it does |
|---|---|
| Spec-driven generators (written in assembly) | WebIDL to bindings, CSS property tables and parsers, HTML parser tables, Unicode tables, builtin stubs, protocol codecs: thousands of lines produced from data |
| Test oracles | Web Platform Tests, test262 and conformance data decide done-ness; red/green dashboards drive priorities |
| Corpus-driven priorities | an offline archive of top-site pages ranks missing features by real impact, so effort goes where users feel it |
| Reuse of your own libraries | `lib/str` for Unicode, `crypto/` for TLS, X.509 and primitives, `unet/http` for HTTP/1.1 to HTTP/3, `unet/anon` for Tor cells and obfs4, `lib/ucmp` for decompression, `lib/canvas` for display, fonts and images |
| Assembly productivity layer | shared macros, calling conventions, structured control-flow macros, a linter and debug allocators; written once, used everywhere |
| AI-assisted writing with oracle tests | every module is accepted only when its tests pass |
| Release gating | no release starts until the scoreboard is met |

If the 100%-assembly rule were ever relaxed for the long tail, the timeline would
shrink a lot. This plan does **not** assume that.

## 4. One browser: normal by default, containers built in, Tor on a switch

ubrowse is a normal browser first. The full web platform is available everywhere;
what changes is how much state is kept and which network carries it. Every window is
one of three modes, and inside Normal and Private windows every tab sits in a
container.

| | **Normal** (default) | **Private** | **Tor** (switched on) |
|---|---|---|---|
| Network | direct; any container can be switched to Tor routing | direct; Tor routing per container | Tor only, fails closed |
| Containers | yes, persistent | yes, held in memory | no; every site already isolated, New Identity instead |
| State | partitioned by container and site, persistent | amnesic | amnesic |
| Tracking protection | built-in blocker, partitioned storage, third-party cookies denied | same plus stronger fingerprint protection | same plus blend profile |
| JIT, WebAssembly | on | on | off at Safer and Safest |
| WebGL, WebGPU | on, with fingerprint hardening | on, hardened | off |
| WebRTC | on, no local-IP leaks | relay-only | off |
| Audio and video | on, autoplay blocked | on | click-to-play, no autoplay |
| Service workers, push | on | off | off |
| Extensions | on | on, restricted | signed only, restricted |
| Web fonts | on | on | blocked at Safer and Safest |
| Persistent storage | on | off | off |

**Tor mode security levels:** **Safest** (no JS, no web fonts, static images only),
**Safer** (default; JS only on HTTPS and onion pages with filtered APIs, no JIT, no
web fonts), **Standard** (JS on with filtered APIs). Levels can be tightened per site
but never silently loosened.

### 4.1 Multi-account containers (native)

Containers work like Firefox Multi-Account Containers, but they are part of the
browser, not an add-on, so the engine, network, Tor client and storage all know about
them.

| Feature | Behaviour |
|---|---|
| Containers | create, edit and delete with a name, colour and icon; defaults are Personal, Work, Banking and Shopping; "No container" is the plain default |
| Tab identity | container colour on the tab and a label in the URL bar, so you always see which account you are in |
| Open in | new tab in a container (menu and keyboard shortcut per container), reopen the current tab in another container, open link in container |
| Site assignment | "always open this site in Work": the browser offers to switch when the site is opened elsewhere; can be set to switch without asking |
| Temporary containers | a fresh throwaway container per tab, deleted with all its data when the tab closes |
| What is separated | cookies, `localStorage`, IndexedDB, Cache API, HTTP cache, service workers, HTTP auth, TLS session tickets, HSTS state, connection pools, site permissions, Tor circuits |
| What is shared | history and bookmarks by default (each can be set to per-container); saved passwords can be pinned to a container |
| Tab management | sort tabs by container, hide or show one container's tabs, move a container's tabs to a new window |
| Clear | clear one container's data without touching the others |
| Tor routing | per container: "route this container over Tor" (section 4.2) |

Containers are part of the partition key (section 12), so isolation is enforced in one
place: `lib/web` only ever sees an opaque key, and every store, cache, connection and
circuit is looked up by it.

### 4.2 The Tor switch

Tor is a feature you turn on, not the browser's identity. Until it is switched on the
first time, nothing Tor-related runs: no bootstrap, no directory fetch, no connection to
any relay. The Tor client is the `unet/anon/tor` library; ubrowse only decides which
traffic goes to it.

| Switch | What you get | What it protects |
|---|---|---|
| **New Tor window** | full Tor mode from the table above: Tor-only network, amnesic, security levels, blend profile, letterboxing | IP address and fingerprint; built to blend with the Tor Browser crowd |
| **Route a container over Tor** | that container's tabs use Tor circuits (one per site); its cookies and logins stay as they are | IP address only. The UI says plainly that this is not anonymity, because the container keeps its state and the normal fingerprint |

Rules that hold for both:

- **Never mixed.** A page loads entirely over Tor or entirely direct. Switching
  closes the container's connections and reloads its tabs; nothing in flight leaks out
  the other way.
- **Fails closed.** If Tor drops while switched on, requests fail with a clear error
  page. There is no silent fallback to direct.
- **Switching back warns.** Turning Tor routing off for a container offers "switch and
  clear this container", because cookies set over Tor would otherwise travel direct.
- **Onion addresses** opened in a direct window offer "open in a Tor window".
- **Status is visible.** Tor windows and Tor-routed containers carry the Tor indicator,
  and the circuit view shows the path for the current site.

## 5. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ Browser process: UI, tabs, profiles, permissions, policy, updates     │
├───────────────┬───────────────┬───────────────┬──────────────────────┤
│ Renderer      │ Network       │ Tor           │ GPU / compositor     │
│ (one per site)│ (direct mode) │ (own domain)  │  raster, composite   │
│  html, css,   │  http1/2/3,   │  link, cells, │  via Canvas GPU      │
│  layout,      │  tls profile, │  circuits,    │                      │
│  js + JITs,   │  cache, cookies│ onion svcs,  ├──────────────────────┤
│  web apis     │               │  bridges      │ Utility (sandboxed)  │
│               │               │               │  media, image, font, │
│               │               │               │  pdf decoders        │
├───────────────┴───────────────┴───────────────┴──────────────────────┤
│ IPC (handles only) · hardware sandbox · CET shadow stack · W^X        │
├──────────────────────────────────────────────────────────────────────┤
│ Canvas client library, Tattva services (see section 6)                │
└──────────────────────────────────────────────────────────────────────┘
```

**Network rule (single egress gate):** only the Tor process and the Network process
(direct mode) may open sockets. Renderers, the GPU and utility processes have **no
network access at all**.

**Process model:** one renderer process per site (site isolation), a separate Network
process, a separate **Tor process in its own protection domain**, a GPU/compositor
process, and short-lived sandboxed utility processes for decoding untrusted media,
images, fonts and PDFs.

### 5.1 Where the code lives

The browser is split so that **rendering ends at `lib/web`**. Everything that turns
bytes into a page (HTML, CSS, DOM, layout, text, paint, JavaScript, Web APIs) is a
library; everything that makes it a browser (tabs, chrome, modes, Tor choice, profile,
updates) is the app.

| Home | Owns | Does not own |
|---|---|---|
| `lib/web/` | URL, fetch algorithm and web security policy (CORS, CSP, SRI, referrer, sandbox flags), HTML, DOM, CSS, layout, text layout, paint to a display list, images glue, forms, accessibility tree, JS engine, DOM bindings, Web APIs, API-gate mechanism | sockets, files, UI chrome, mode and level policy, Tor, persistence |
| `apps/ubrowse/` | browser process, tabs, containers, the Tor switch, site partitions, navigation and session history, UI chrome, modes and security levels (policy data), egress gate, request filters, local-network block, HTTPS-first and HSTS store, TLS profile, blend profile, vault and profile storage, updates, process model, extensions, devtools front end, sync, passwords | anything another app could reuse to render a page |
| `crypto/` | AES-CTR, SHA-1, SHA-3/SHAKE, HKDF, Argon2id, Ed25519 with blinding, RSA, P-256, constant-time bignum, Elligator 2, X.509, TLS 1.3 with certificate and ClientHello hooks | browser policy |
| `unet/anon/tor/` | the Tor client (link, circuits, streams, directory, paths, onion services, bridges, test network); `unet/anon/obfs4.asm` already exists | which sites use Tor |
| `unet/http/`, `unet/dns/` | HTTP/1.1, HTTP/2 with HPACK, HTTP/3 with QPACK and QUIC, WebSocket, SSE, WebTransport, DNS (direct mode only); most files already exist | cookies, cache, CORS (those are `lib/web`) |
| `lib/str`, `lib/ucmp`, `lib/urand`, `lib/mem`, `lib/canvas` | Unicode and segmentation, gzip/deflate/brotli, CSPRNG, hardened allocator, surfaces, fonts, PNG/JPEG/GIF | web semantics |

**Why `lib/web` and not `lib/browse`:** the library implements the *web platform*, not
the act of browsing. Its other consumers are not browsers: HTML mail in a messaging
app, in-app help and documentation pages, reader and print rendering, headless page
rendering for tests and the corpus harness, and an embeddable web view for other
apps. Naming it after the app would invite browser policy into it. `lib/web` is
separate from `lib/serve/uweb`, which serves web apps; that adapter does not render.

**The embedder boundary.** `lib/web` never opens a socket, touches a file, reads the
real clock or draws chrome. The embedder (ubrowse, or any other app) hands each page:

| Provider | Supplied by ubrowse as |
|---|---|
| network transport | the egress gate: `unet/http` in direct mode, `unet/anon/tor` in Tor mode, chosen per partition |
| storage | partitioned stores in RAM (Private, Tor) or the vault (Normal) |
| policy table | which APIs exist and how they behave for the current mode and level (section 4) |
| clock and entropy | coarsened clock (100 ms in Tor mode), `lib/urand` |
| display target | a Canvas surface; `lib/web` emits a display list, the app composites it under its chrome |

This keeps the single egress gate (section 5) true by construction: the engine has no
way to reach the network except through what the app passes in.

Phases homed in a shared library (`crypto/`, `unet/`) are planned and counted here
because the browser needs them first, but they land in that library and follow its
conventions. Where a file already exists there, the phase audits and extends it
instead of writing a new one.

## 6. What the browser needs from Tattva and Canvas

These are **not browser work**, but they **gate** the later releases. They are listed
in `docs/tattva-contract.md` so Tattva can plan them.

| Requirement | Owner | Gates |
|---|---|---|
| **Hardware process isolation** (paging, ring 3, per-process address spaces) | Tattva | R3 sandbox; the whole security pillar |
| Message passing, shared memory and handle passing between processes | Tattva | R3 |
| Threads and multi-core scheduling (SMP) | Tattva | R2 workers, R3 off-main-thread work |
| W^X memory control (map writable, then executable) | Tattva | R3 JITs |
| CPU hardening: NX, SMEP/SMAP, CET shadow stack and IBT, ASLR | Tattva | R3 |
| High-resolution clock, RTC, power management | Tattva | battery and startup targets |
| UDP sockets | Tattva | HTTP/3, WebRTC |
| TLS with certificate and ClientHello hooks | Tattva | R1 (decision D1) |
| Durable filesystem with quotas | Tattva | storage, vault |
| Audio output | Tattva | R4 media |
| Camera and microphone drivers | Tattva | R4 devices |
| GPU acceleration and scanout planes | Canvas (C24) | R3 raster, R4 WebGL/WebGPU |
| Color management and HDR | Canvas (C25) | R4 HDR video |
| Window states, clipboard, input methods, accessibility | Canvas (C13, C15, C16) | R1 onward |

**Decision D2 (needs your call before R3):** is hardware process isolation (and SMP,
W^X, CET) on Tattva's roadmap? Without it, the security and speed rows of the
scoreboard cannot be met, because renderers would share one address space and JITs
could not be made safe.

## 7. Security architecture

| Layer | Measure |
|---|---|
| Isolation | process per site, hardware sandbox, no network or filesystem access for renderers, handles-only IPC |
| Memory safety (assembly has none built in) | bounds-checked buffer wrappers, per-process arenas with guard pages, hardened allocator, zeroization on free, debug allocator with red zones, RSO ownership rules, fuzzing from day one |
| Control-flow | CET shadow stack and indirect-branch tracking, no executable and writable memory at once |
| JIT | W^X, constant blinding, guard pages around code, separate JIT-compile step with validation, JIT off in Tor Safer and Safest |
| Spectre-class | site isolation, coarse timers, `SharedArrayBuffer` only with cross-origin isolation |
| Parsers of untrusted data | HTML, CSS, JS, media, images, fonts, PDF: fuzzed continuously, decoders run in sandboxed utility processes |
| Web security model | same-origin, CSP, CORS, COOP/COEP/CORP, Trusted Types, SameSite, Fetch Metadata, permissions policy |
| Supply chain | reproducible builds, signed updates with multiple signers, pinned data (roots, HSTS, authorities) with freshness checks |
| Assurance | external audits, bug bounty, public security advisories |

## 8. Privacy architecture

| Principle | Concrete rule |
|---|---|
| Private by construction | no telemetry, no accounts, no update pings, no speculative requests (outside the user's chosen mode) |
| Single egress gate | only the Tor and Network processes touch sockets |
| Partitioned everything | cookies, cache, storage, connections, TLS tickets, HSTS and Tor circuits are keyed by container and top-level site |
| Amnesic where promised | Private and Tor modes keep state in RAM and zeroize on close |
| Deny by default | permissions start denied |
| No local-network reach | web content cannot reach loopback, private or link-local addresses |
| Transparent | a built-in privacy panel lists every request, what was blocked, which circuit carried it, and what each site may learn |

**Fingerprint surface and defenses** (strict in Tor mode, hardened in Private and
Normal):

| Vector | Defense |
|---|---|
| User-Agent, `navigator.*`, headers and order | fixed profile values |
| TLS ClientHello, HTTP/2 settings | profile-controlled to match the blend target |
| Window and screen size | letterboxing to fixed buckets (Tor mode) |
| Fonts | bundled fonts in Tor mode; system font list never exposed |
| Canvas, WebGL, WebAudio | readback gated or noised per site |
| Timers | 100 ms resolution in Tor mode, coarsened elsewhere |
| Locale, timezone | fixed in Tor mode |
| Hardware details | not exposed |
| Engine quirks (error text, `toString`, enumeration order) | match the blend target where observable |

**Blend decision (needs your call before B39):** the recommended target is the
**Tor Browser crowd** (emulate its observable behavior). Option B is a single fixed
profile for this browser only, which is simpler but gives a much smaller crowd.

**Safety statement for the README:** until independent audits and review by Tor
community engineers, this software should not be presented as safe for people at high
risk. A custom Tor client and a custom engine are both security-critical.

## 9. Tor subsystem

A **client only**, in `unet/anon/tor/`, running in its own protection domain from R3,
behind a narrow interface so other Utkarsha software can reuse it.

```
tor_start() / tor_stop() / tor_status()
tor_open_stream(host, port, isolation_key)  -> stream handle
tor_stream_send / tor_stream_recv / tor_stream_close
tor_new_identity()          tor_new_circuit(isolation_key)
tor_circuit_info(isolation_key)             -> path description for the UI
tor_bridges_set(list)
```

| Component | Role |
|---|---|
| Link layer | TLS to relays, version negotiation, `CERTS`, `AUTH_CHALLENGE`, `NETINFO`, link certificate checks |
| Cells and circuits | cell codec, ntor handshake, `EXTEND2`, layered relay encryption and digests, teardown |
| Streams | `BEGIN`, `CONNECTED`, `DATA`, `END`, authenticated `SENDME`, DNS by exit, connection padding |
| Directory | authority and fallback lists, consensus fetch and signature verification, microdescriptors, caching, freshness, time sanity from the consensus |
| Path selection | guard sets with persistent state, bandwidth weighting, family and subnet rules, exit policy, build timeouts, circuit pool |
| Isolation | circuit set per site partition; `New Identity` wipes and rebuilds |
| Onion services v3 | address parsing, key blinding, directory ring, descriptor decryption, introduction, rendezvous, client authorization |
| Bridges and transports | bridge lines, obfs4, meek, webtunnel |
| Hardening | circuit padding, congestion control, conflux, vanguards-style protection, onion-service proof-of-work client |

Requirements: DNS is never resolved locally; the client follows consensus parameters
(good network citizenship); a local **test network** (authority and relays written for
tests) lets circuits be built end to end with no internet.

**Crypto:** most primitives already exist in `crypto/` (`uhash` has SHA-3, `ukdf` has
HKDF and Argon2, `usign` has Ed25519, ECDSA and RSA). Phase B3 audits them and adds
only what is missing, inside `crypto/`: AES-CTR, SHA-1, SHAKE, Ed25519 key blinding,
Elligator 2, constant-time bignum.

## 10. Web platform scope

Everything below is **in scope**, ordered by release. "Gated" means available but
restricted in some modes (section 4).

| Area | Scope | Release |
|---|---|---|
| HTML, DOM | full HTML parser, DOM, mutation observers, ranges, selections | R1 to R2 |
| CSS | cascade and layout (block, inline, floats, tables, flex, grid), modern features (container queries, `:has()`, nesting, `@layer`, `@scope`, subgrid, logical properties, color spaces, math functions) | R1 to R2 |
| Animations | transitions, animations, Web Animations, scroll-driven, view transitions | R2 |
| Text | line breaking, bidi, shaping (Latin, Indic including Devanagari, Arabic, Hebrew, Thai, Khmer), vertical text, variable and color fonts, WOFF and WOFF2 | R1 to R2 |
| Intl | full `Intl` API on top of `ustr` | R2 |
| Images | PNG, JPEG, GIF, WebP, SVG, later AVIF and JPEG XL | R1 to R4 |
| JavaScript | ES2020 and later: interpreter (R2), baseline JIT and optimizing JIT (R3) | R2 to R3 |
| Web Components | custom elements, shadow DOM, templates, slots | R2 |
| Network | fetch, XHR, WebSocket, SSE, streams, HTTP/1.1, HTTP/2, HTTP/3 and WebTransport (direct mode), CORS, CSP | R1 to R2 |
| Storage | cookies, `localStorage`, IndexedDB, Cache API, OPFS (all partitioned) | R2 |
| Workers | dedicated and shared workers, structured clone, message channels | R2 |
| Service workers | install, fetch events, push, background sync (privacy-gated) | R4 |
| Editing and forms | `contenteditable`, clipboard, drag and drop, all input types, validation, autofill | R2 |
| Security platform | Trusted Types, COOP/COEP/CORP, permissions policy, Fetch Metadata | R2 |
| Accessibility | full ARIA mapped to the Canvas accessibility tree | R2 |
| Print | paged media, print to PDF | R2 |
| Media | MP4, WebM and Ogg containers; Opus, Vorbis, FLAC, MP3, AAC; VP8, VP9, AV1, H.264; MSE, WebVTT, picture-in-picture, media session, hardware decode (patent-encumbered codecs need a licensing decision) | R4 |
| Web Audio | graph, worklets | R4 |
| WebAssembly | validator, interpreter, baseline and optimizing compilers, threads under cross-origin isolation | R4 |
| Graphics | Canvas 2D, OffscreenCanvas, WebGL 1 and 2, WebGPU with a shader compiler | R4 |
| WebRTC | peer connections, data channels, ICE (relay-only in Private, off in Tor) | R4 |
| Devices (gated, off in Tor) | WebAuthn and passkeys, gamepad, USB, Bluetooth, Serial, HID, geolocation, sensors, camera, microphone, screen capture | R4 |
| PDF | built-in viewer with its own parser, fonts, rendering and forms | R4 |
| PWA | manifest, install, offline | R2 and R4 |

**Known external blocker:** premium streaming sites rely on proprietary DRM (Widevine,
FairPlay, PlayReady) that requires licensing agreements with vendors. This plan covers
ClearKey only; supporting those services is outside what code alone can solve.

## 11. Product features

| Area | Feature | Release |
|---|---|---|
| Privacy | Normal, Private and Tor modes, Tor switch, privacy panel, built-in tracker and ad blocker, HTTPS-first, cookie-banner handling, per-site permissions, panic key | R1 to R2 |
| Tor switch | off by default; Tor windows and per-container Tor routing, per-site circuits, New Identity, circuit viewer, bridges, onion services first-class, `Onion-Location`, onion-only mode | R1 to R2 |
| Tabs | tab groups, vertical tabs, split view, sleeping tabs, session restore (encrypted) | R5 |
| Containers | native multi-account containers: colours and icons, site assignment, temporary containers, per-container Tor routing, per-container clear (section 4.1) | R1 |
| Passwords | password manager, passkeys, autofill, breach check done privately over Tor | R5 |
| Sync | end-to-end encrypted, self-hostable: bookmarks, history, passwords, tabs | R5 |
| Extensions | WebExtensions-style API (Manifest V3 subset), permissions, content scripts, signed distribution | R4 |
| DevTools | DOM and CSS inspector, console, JS debugger, network panel, performance and memory profilers, storage inspector, remote debugging | R4 |
| PDF | viewer with forms and annotation | R4 |
| Reading | reader mode, text-only mode | R1 |
| Downloads | download manager with safe handling, no auto-open | R1 |
| Enterprise | managed policy files, audit logs, remote management, certificate management, kiosk mode | R5 |
| Updates | signed, delta, staged rollout, rollback, reproducible-build verification | R2 and R5 |
| Accessibility | full keyboard operation, screen-reader support, high contrast, caret browsing | R2 |
| Localization | UI in many languages, right-to-left UI, themes, import from other browsers | R5 |

## 12. Core structures (draft)

- **Partition key:** `(mode, container ID, top-level site hash)`. Every storage, cache,
  connection and circuit lookup carries one; `lib/web` treats it as opaque. The Tor
  isolation key is the partition key, so circuits are per container and per site.
- **Container:** `id, name, colour, icon, flags (temporary, Tor-routed), site
  assignments`.
- **IPC handle:** capability-style handle with generation, valid only inside the
  process that received it.
- **DOM node** (64 bytes, `u32` indices): type, flags, tag, parent, first/last child,
  siblings, attribute list, text offset, style and box indices.
- **Cell** (Tor): fixed-size record with circuit ID, command and payload.
- **Circuit:** `id, state, hops[3..], per-hop keys and digests, isolation key,
  stream table, build time`.
- **JS value:** NaN-boxed 64 bits; objects use shapes and inline caches.
- **Request:** `partition key, URL, method, headers, initiator, destination type,
  mode`.

## 13. Phase table

Legend: `☐` planned, `◐` in progress, `✓` shipped. Sizes are **rough lower-bound
estimates** of assembly lines. **Home** is where the code lands, from the repository
root (section 5.1); "all homes" means each home gets its own share.

### Release R1: Everyday core (about 145k)

**Track A: Foundation**

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B0 | Build + Tattva binding | `apps/ubrowse` | build files; `tv_*` bindings for sockets, clock, entropy, TVFS, tasks, log | 1k | ☐ |
| B1 | Browser base | `lib/web` | float parse and format, sort, UTF-16, big-integer helpers, binding to `ustr` | 1k | ☐ |
| B2 | Test harness | all homes | unit macros, serial reporting, mock network, packet recorder, golden harness | 1k | ☐ |

**Track B: Crypto**

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B3 | Crypto audit + symmetric | `crypto/` | audit Tattva crypto; add AES-CTR, SHA-1, SHA-3/SHAKE, HKDF if absent | 5k | ☐ |
| B4 | Public-key additions | `crypto/` | Ed25519 with blinding, X25519 and ECDSA if absent, RSA verify, constant-time bignum | 6k | ☐ |
| B5 | KDF and RNG | `crypto/`, `lib/urand` | Argon2id, CSPRNG with entropy mixing, constant-time helpers | 2k | ☐ |

**Track C: Tor client** (the `unet/anon/tor` library behind the Tor switch; built after direct browsing works, see section 15)

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B6 | Link layer | `unet/anon/tor` | TLS to relays with custom verification, versions, `CERTS`/`NETINFO`, link certificates, cell codec | 3k | ☐ |
| B7 | Circuits | `unet/anon/tor` | ntor, `EXTEND2`, relay crypto layers, digests, teardown | 4k | ☐ |
| B8 | Streams + flow control | `unet/anon/tor` | `BEGIN`/`DATA`/`END`, authenticated `SENDME`, DNS by exit, connection padding | 3k | ☐ |
| B9 | Directory | `unet/anon/tor` | authority and fallback lists, consensus fetch and verification, microdescriptors, caching | 6k | ☐ |
| B10 | Paths + guards | `unet/anon/tor` | guard sets and persistence, weighted selection, family rules, exit policy, build timeouts, pool, isolation | 4k | ☐ |
| B11 | Tor interface | `unet/anon/tor` | `tor_*` API, bootstrap progress, failures, New Identity | 1.5k | ☐ |
| B12 | Onion services v3 | `unet/anon/tor` | address and blinding, directory ring, descriptor decrypt, introduction, rendezvous, authorization | 8k | ☐ |

**Track D: Network and loader**

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B15 | HTTP/1.1 + loader core | `lib/web/fetch`, `unet/http` | URL parser, HTTP/1.1, content decoding including brotli, redirects, partitioned cookie jar and cache | 8k | ☐ |
| B17 | TLS profile + trust | `crypto/utls`, `apps/ubrowse` | ClientHello profile, root store, name checks, HSTS preload, HTTPS-first (B17b: own TLS 1.3 client if decision D1 requires) | 5k | ☐ |
| B18 | Security policies | `lib/web/fetch`, `apps/ubrowse` | CSP, CORS, referrer policy, sandbox, SRI, filter engine, local-network block, no-speculation rules | 6k | ☐ |
| B19 | Storage + vault | `apps/ubrowse` | partitioned state manager, encrypted vault, zeroization, session wipe | 5k | ☐ |

**Track E: Rendering engine (static web)**

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B20 | HTML + DOM | `lib/web` | tokenizer, tree builder, entities, DOM operations, serialization | 6k | ☐ |
| B21 | CSS | `lib/web` | tokenizer, parser, values, selectors, cascade, computed style, variables, media queries | 9k | ☐ |
| B22 | Layout | `lib/web` | box tree, block, inline, floats, positioning, lists, tables, overflow | 12k | ☐ |
| B24 | Paint + compositing | `lib/web` | paint tree, scrolling, hit testing, selection, high DPI, Canvas surfaces | 4k | ☐ |
| B25 | Text | `lib/web` | line breaking, bidi, shaping (Latin, then Devanagari and others), bundled fonts | 9k | ☐ |
| B26 | Images | `lib/web` | glue for Canvas decoders, WebP, animation control | 4k | ☐ |
| B27 | Forms, input, a11y | `lib/web` | form controls, text editing, input methods, accessibility tree | 6k | ☐ |

**Track G: Shell, containers and blending**

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B35 | Browser core | `apps/ubrowse` | tabs, site partitions, tab tasks, navigation, session history, permissions, downloads, find, reader mode, error pages | 6k | ☐ |
| B36 | UI chrome | `apps/ubrowse` | tab strip with container colours, URL bar with HTTPS, container, Tor and onion indicators, Tor switch, privacy panel, circuit view, levels, New Identity, settings | 5k | ☐ |
| B91 | Containers | `apps/ubrowse` | container model and store, defaults, colours and icons, open and reopen in container, site assignment, temporary containers, per-container clear, per-container Tor routing, container-aware session restore | 5k | ☐ |
| B37 | Start page + search | `apps/ubrowse` | offline start page, search providers, no leaking suggestions | 2k | ☐ |
| B39 | Blend profile | `apps/ubrowse` | UA, header order, TLS hello, HTTP/2 settings, window buckets, engine-quirk matching, fingerprint test suite | 3k | ☐ |
| B40 | Leak harness | `apps/ubrowse` | packet-level tests: with Tor off nothing touches the Tor network; with Tor on only Tor link connections leave for Tor traffic; switching never mixes; no state crosses containers; DNS, referrer, timing, local-network checks | 2k | ☐ |

### Release R2: Modern web (about 340k)

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B13 | Bridges + obfs4 | `unet/anon` | bridge lines, obfs4 with Elligator 2 | 8k | ☐ |
| B14 | Advanced Tor | `unet/anon` | meek and webtunnel, circuit padding, congestion control, conflux, vanguards-style protection, onion PoW client, test network | 8k | ☐ |
| B16 | HTTP/2 | `unet/http` | HPACK, streams, flow control, settings control | 5k | ☐ |
| B23 | Flexbox + Grid | `lib/web` | flexbox, grid layout | 7k | ☐ |
| B28 | JS lexer + parser | `lib/web` | ES2020 syntax to AST | 6k | ☐ |
| B29 | JS compiler + VM | `lib/web` | bytecode, stack VM, closures, exceptions, shapes, inline caches | 7k | ☐ |
| B30 | JS values + GC | `lib/web` | NaN-boxing, objects, strings, atoms, precise GC | 6k | ☐ |
| B31 | JS builtins | `lib/web` | standard library | 14k | ☐ |
| B32 | JS event loop | `lib/web` | microtasks, promise jobs, timers | 3k | ☐ |
| B33 | DOM + Web APIs | `lib/web` | DOM bindings, events, `fetch`, XHR, storage, history, URL | 8k | ☐ |
| B34 | Privacy shims | `lib/web`, `apps/ubrowse` | API gating by mode and level, canvas protection, timer clamp, navigator constants, screen bucketing | 3k | ☐ |
| B38 | Updates + reproducibility | `apps/ubrowse` | signed manifests, threshold signatures, update over Tor, reproducible build tooling | 3k | ☐ |
| B45 | Streaming network APIs | `lib/web`, `unet/http` | WebSocket, SSE, fetch streaming, streams API | 6k | ☐ |
| B46 | Workers | `lib/web` | dedicated and shared workers, structured clone, message channels | 8k | ☐ |
| B47 | Storage APIs | `lib/web` | IndexedDB, Cache API, OPFS, quota, all partitioned | 14k | ☐ |
| B48 | Web Components | `lib/web` | custom elements, shadow DOM, templates, slots | 12k | ☐ |
| B49 | Modern CSS | `lib/web` | container queries, `:has()`, nesting, `@layer`, `@scope`, subgrid, logical properties, color spaces, math functions | 20k | ☐ |
| B50 | Animations | `lib/web` | transitions, animations, Web Animations, scroll-driven, view transitions | 15k | ☐ |
| B51 | SVG + MathML | `lib/web` | full SVG, MathML | 30k | ☐ |
| B52 | Fonts | `lib/web` | WOFF and WOFF2, variable fonts, color fonts, font features, Arabic, Hebrew, Thai, Khmer shaping, vertical text | 20k | ☐ |
| B53 | Intl | `lib/web` | complete `Intl` on top of `ustr`: collation, plural rules, date, number, list and relative-time formatting | 25k | ☐ |
| B54 | Editing | `lib/web` | `contenteditable`, selection and range APIs, `execCommand`, input events, clipboard API, drag and drop | 25k | ☐ |
| B55 | Security platform | `lib/web` | Trusted Types, COOP/COEP/CORP, permissions policy, Fetch Metadata, CSP3, cookie standards | 12k | ☐ |
| B56 | Print | `lib/web` | paged media, print to PDF | 10k | ☐ |
| B57 | Forms complete | `lib/web` | all input types, validation, datalist, date and color pickers, file picker, autofill | 20k | ☐ |
| B58 | HTTP/3 + QUIC | `unet/http`, `lib/web` | QUIC, HTTP/3, WebTransport (direct mode only; Tor does not carry UDP) | 25k | ☐ |
| B59 | Accessibility | `lib/web` | full ARIA, accessibility tree to Canvas, focus and caret browsing | 15k | ☐ |
| B60 | PWA basics | `lib/web`, `apps/ubrowse` | manifest, install, offline shell | 5k | ☐ |

### Release R3: Fast and hardened (about 300k)

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B61 | Process model + hardware sandbox | `apps/ubrowse` | browser, renderer-per-site, network, Tor, GPU and utility processes; handles-only IPC; sandbox policy (**needs Tattva isolation, decision D2**) | 30k | ☐ |
| B62 | Hardening | `lib/mem`, `apps/ubrowse` | CET shadow stack and IBT, hardened allocator with guard pages, zeroization, debug allocator with red zones | 6k | ☐ |
| B63 | Baseline JIT | `lib/web` | template JIT for the bytecode VM, W^X handling, deoptimization hooks | 40k | ☐ |
| B64 | Optimizing JIT | `lib/web` | type feedback, inlining, escape analysis, register allocation, deoptimization | 90k | ☐ |
| B65 | Garbage collector v2 | `lib/web` | generational, incremental and concurrent marking, compaction, off-thread parsing and compilation | 25k | ☐ |
| B66 | Layout and style performance | `lib/web` | incremental layout, parallel style, SIMD text measurement, layers | 30k | ☐ |
| B67 | GPU raster + compositor | `lib/web`, `lib/canvas` | tile-based rasterization, GPU compositing, off-main-thread scrolling (**needs Canvas C24**) | 50k | ☐ |
| B68 | Memory and startup | `lib/web`, `apps/ubrowse` | snapshots, lazy init, tab discarding, memory-pressure handling | 10k | ☐ |
| B69 | Network performance | `apps/ubrowse` | pooling, prioritization, preload scanner (disabled across sites in Tor mode), cache tuning | 12k | ☐ |
| B44 | First external audit | `apps/ubrowse` | documentation, threat model, audit package, remediation | 3k | ☐ |

### Release R4: Full platform (about 680k)

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B70 | Media I | `lib/web` | containers (MP4, WebM, Ogg), audio and video codecs, audio output | 70k | ☐ |
| B71 | Media II | `lib/web` | media elements, MSE, WebVTT, picture-in-picture, media session, hardware decode | 30k | ☐ |
| B72 | Web Audio | `lib/web` | audio graph, worklets | 20k | ☐ |
| B73 | WebAssembly | `lib/web` | validator, interpreter, baseline and optimizing compilers, threads | 80k | ☐ |
| B74 | Canvas 2D + images | `lib/web` | full Canvas 2D, OffscreenCanvas, image bitmaps, AVIF and JPEG XL | 30k | ☐ |
| B75 | WebGL | `lib/web` | WebGL 1 and 2, shader translation for the chosen GPU family | 60k | ☐ |
| B76 | WebGPU | `lib/web` | WebGPU and a WGSL compiler | 60k | ☐ |
| B77 | Service workers | `lib/web` | install, fetch events, push, background sync, notifications | 25k | ☐ |
| B78 | WebRTC | `lib/web`, `unet` | peer connections, data channels, ICE, codecs | 70k | ☐ |
| B79 | Device APIs | `lib/web`, `apps/ubrowse` | WebAuthn, gamepad, USB, Bluetooth, Serial, HID, geolocation, sensors, camera, microphone, screen capture | 35k | ☐ |
| B80 | PDF viewer | `apps/ubrowse` | PDF parser, fonts, rendering, forms, annotation | 50k | ☐ |
| B81 | Extensions | `apps/ubrowse` | WebExtensions-style API, permissions, content scripts, signing | 40k | ☐ |
| B82 | DevTools | `apps/ubrowse`, `lib/web` | inspectors, console, debugger, network, profilers, remote debugging protocol | 90k | ☐ |
| B83 | Compatibility program | `apps/ubrowse` | top-site corpus harness, WPT tracking, quirks database, triage tooling | 20k | ☐ |

### Release R5: Product and ecosystem (about 105k)

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B84 | Tabs | `apps/ubrowse` | tab groups, vertical tabs, split view, sleeping tabs, encrypted session restore (containers moved to B91 in R1) | 18k | ☐ |
| B85 | Sync | `apps/ubrowse` | end-to-end encrypted, self-hostable sync server and client | 25k | ☐ |
| B86 | Passwords + passkeys | `apps/ubrowse` | password manager, passkeys, autofill, private breach check | 15k | ☐ |
| B87 | Enterprise | `apps/ubrowse` | managed policy, audit logs, remote management, certificate management, kiosk mode | 20k | ☐ |
| B88 | Updates at scale | `apps/ubrowse` | delta updates, staged rollout, rollback, supply-chain verification | 10k | ☐ |
| B89 | Localization | `apps/ubrowse` | UI languages, right-to-left UI, themes, import from other browsers | 10k | ☐ |
| B90 | v1.0 release | `apps/ubrowse` | audits, bug bounty, opt-in privacy-preserving crash reports, scoreboard publication | 5k | ☐ |

### Continuous (every release)

| # | Phase | Home | Deliverable | Est. lines | Status |
|---|---|---|---|---|---|
| B41 | Fuzzing | all homes | HTML, CSS, JS, URL, HTTP, HPACK, brotli, WebP, cells, consensus, descriptors, plus new parsers as they appear | 3k | ☐ |
| B42 | Conformance | all homes | agreed subsets of Web Platform Tests and test262, run as data; top-site corpus | n/a | ☐ |
| B43 | Performance | all homes | benchmark and budget tracking against the scoreboard | n/a | ☐ |

**Rough totals (lower bound):** about **1.6 million lines**; plan for 2 to 3 million.

## 14. Milestones

| # | Name | After | What you can see |
|---|---|---|---|
| BM1 | HTTPS fetch | B15 + B17 | headless: fetch a page directly over HTTPS and print the text on serial |
| BM2 | First page | B20 to B24 | a static page rendered in a Canvas window, loaded directly |
| BM3 | Two accounts | B35 + B91 | the same site signed in to two different accounts in two containers, side by side |
| BM4 | Tor switch | B11 + B36 | switch on Tor for a window or a container and load the same page over a three-hop circuit; switch off and it loads direct |
| BM5 | Onion | B12 | open a `.onion` address in a Tor window |
| BM6 | **R1: Everyday browser** | R1 complete | normal browsing with containers, Tor switch, privacy panel, blend profile in Tor windows, leak harness green; scoreboard R1 met |
| BM7 | **R2: Modern web** | R2 complete | JS, flex and grid, workers, storage, components; most everyday sites work |
| BM8 | **R3: Fast and safe** | R3 complete | process-per-site sandbox, JITs, GPU raster; first external audit |
| BM9 | **R4: Full platform** | R4 complete | media, WebAssembly, WebGL, WebRTC, PDF, extensions, devtools |
| BM10 | **v1.0** | R5 complete | sync, passkeys, enterprise, bug bounty live; scoreboard v1.0 met |

## 15. Order of work

1. **R1, direct browsing first:** B0 to B5, B15, B17 to B19 need no display and can be
   built while Canvas is still being written. Most of this lands in `crypto/` and
   `unet/`, so start each phase by auditing what those libraries already have.
2. **R1, rendering, shell and containers:** B20 to B27 in `lib/web` can start
   headless (display list checked against golden dumps); B35 to B37 and B91 in the
   app once Canvas reaches CM2. Containers go in with the first shell, not later,
   because the partition key carries them from day one.
3. **R1, Tor switch:** B6 to B12 in `unet/anon/tor`, then the switch wiring in the app,
   B39 and B40. Tor stays off by default the whole time; normal browsing never waits on
   it.
4. **R2:** start with B16, B28 to B34 (JS), then B23, B45 to B60 in the order the
   top-site corpus says users feel them.
5. **Before R3:** resolve decision D2 and the Tattva prerequisites in section 6.
6. **R3:** B61, B62 first (isolation), then B63 to B69.
7. **R4:** B83 (compatibility program) runs first and continuously; the rest follow
   corpus impact.
8. **R5:** B84 to B90.

## 16. Testing and measurement

All tests run on Tattva and report over serial or console.

1. **Unit tests** per module.
2. **Web Platform Tests** (subsets run as data) with a per-area pass-rate dashboard.
3. **test262** for the JavaScript engine.
4. **Top-site corpus:** archived pages and scripted flows (sign-in, search, video, forms)
   with pass/fail rendering checks.
5. **Performance suites:** JS, rendering, page load, startup and memory benchmarks.
   Comparisons against other browsers use the same suites run on **another operating
   system on the same hardware**, purely for measurement.
6. **Leak harness (B40)** and **fingerprint suite (B39)** stay green on every build.
7. **Tor test network:** local authority and relays for end-to-end circuit and onion
   tests with no internet.
8. **Fuzzing and soak tests** for every parser and decoder; continuous.
9. **Security assurance:** external audits at R3 and R5, bug bounty at v1.0.
10. A bug fix lands with a test that fails without it.

## 17. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| **Scale** (2 to 3 million lines) | multi-year effort, may stall | generators, test oracles, corpus-driven priorities, release gating, reusable assembly layer |
| **Compatibility long tail** | users leave when sites break | compatibility program (B83), quirks database, honest error pages |
| **No hardware isolation on Tattva** | security pillar impossible | decision D2; R3 starts only when it exists |
| **Assembly and memory safety** | exploitable bugs | bounds-checked wrappers, guard pages, CET, fuzzing, sandboxing, audits |
| **JIT security and complexity** | large attack surface | W^X, validation, JIT off in strict Tor levels, fuzzing |
| **GPU and codecs** | very large, hardware- and licence-specific | one GPU family first; patent-encumbered codecs need a licensing decision |
| **Proprietary DRM** | premium streaming cannot work | accepted limit; ClearKey only |
| **Custom Tor client bugs** | deanonymization | follow published specs, test network, community review, audit before any high-risk recommendation |
| **Container Tor routing mistaken for anonymity** | users expose themselves while believing they are anonymous | the switch and indicator say "IP privacy only"; anonymity is offered only by Tor windows |
| **Small anonymity set** | users distinguishable | blend profile and fingerprint suite; honest messaging until measured |
| **Stale shipped data** (authorities, roots, HSTS, filters, Public Suffix List) | breakage or privacy loss | signed updates, build-time freshness checks |
| **Tattva TLS lacks hooks** | blocks Tor and blending | decision D1; own TLS client as fallback |
| **Ecosystem** (no extensions or sites targeting you) | adoption | WebExtensions-style API, standards-compliance first |

## 18. Out of scope

Proprietary DRM beyond ClearKey, any operating system other than Tattva, mobile
versions, a Chrome Web Store clone, a browser-based AI assistant, and browser sync
servers run by the project (sync is self-hosted only).

## 19. Definition of done (per phase)

- Assembles with no warnings and links into the Tattva image.
- Code sits in its home from section 5.1; nothing in `lib/web` reaches into
  `apps/ubrowse`.
- Unit tests pass on Tattva; leak and fingerprint suites stay green.
- The scoreboard row for the phase's release is not worse than before.
- Status table updated with the real line count.
- Relevant doc in `docs/` written, including a decision record for any design choice.

# ubt — Roadmap

**Part of:** Utkarsha OS, `lib/ubt` — the Bluetooth library
**Status:** plan only; `lib/ubt` is empty as of 2026-11-04
**Covers:** every Bluetooth Core version from 1.0b to 6.3 (May 2026), plus
the profiles and the Mesh specification built on top of them

`ubt` is the Bluetooth **host**. It drives a Bluetooth **controller** (the
radio chip and its firmware) through the Host Controller Interface (HCI),
and it implements everything above HCI: discovery, connections, pairing,
L2CAP, SDP, ATT/GATT, the profiles, LE Audio, Mesh, Channel Sounding and
the data used by direction finding. It also contains a software controller
(`sim/`). The software controller is a test tool, not something users run.

Every part is built the same way as the rest of the OS:
- pure x86-64 assembly, statically linked;
- runs in ring 0 and is called directly, with no request layer in between;
- every byte that arrives over the air is treated as hostile.

Legend: ✅ done · ◐ exists but unproven · ☐ planned

Line counts are estimates of assembly source, not including tests, and
could be off by ±50%.

---

## 1. Host versus controller: what "every version" means

A Bluetooth version is mostly a list of **controller** features: the radio,
the baseband and the link layer. The host does not implement the radio. For
each version the host needs to do three things:

1. send and parse the new HCI commands and events;
2. implement the host-side protocols that the version adds (for example
   SMP for 4.0, EATT for 5.2, Channel Sounding procedures for 6.0);
3. read what the controller and each peer support, and adapt to it.

So `ubt` supports "all versions" in two senses:

| Sense | Meaning |
|---|---|
| **Controller range** | `ubt` works with any controller from 1.1 to 6.3 and uses every feature that controller reports |
| **Peer range** | `ubt` connects to peers of any version, from a 1.1 headset to a 6.x tag, and limits itself to what both sides support |

Two things from older specifications are deliberately **not** built:

- **AMP / 3.0 + HS** (Bluetooth data over 802.11): withdrawn by the
  specification in 5.3, and no current controller has it. The rest of 3.0
  (Enhanced Retransmission Mode, Streaming Mode, enhanced power control) is
  built.
- **Profiles that have been deprecated or withdrawn** (HDP, BPP, SAP,
  CTP/ICP, FAX, HCRP, DUN, VDP, and others). Section 9 lists what is built.

---

## 2. What enterprise grade means here

| Area | Requirement |
|---|---|
| Safety | No packet from the air or the controller can crash, hang, leak or corrupt the host. Every parser checks lengths and is fuzzed |
| Security | Secure Connections by default, 16-byte encryption keys enforced, every known host-side attack in Section 12 has a fix and a test |
| Interoperability | Pairs and streams with the user's real devices (Section 3) and with a fixed set of reference peers on every release |
| Reliability | Surviving a controller reset, a USB unplug, or a peer that disappears mid-procedure; a dead controller is re-initialised without a reboot |
| Stability | 72 hours of audio streaming, input and LE traffic on real hardware with no leak or stall |
| Latency | HID input: under 1 ms from the controller event to the input queue. Audio: steady stream with no dropouts under full CPU load |
| Observability | Every link, channel, error and retry is counted and readable in `/sys/dev/bt0/`; full packet capture on demand |
| Conformance | Each protocol has a test suite built from the Bluetooth SIG test specifications, run against `sim/` on every build |
| Multi-vendor | MediaTek, Intel, Realtek, Broadcom, Qualcomm and Nordic controllers behave the same behind one interface |
| Manageability | An administrator can set policy (what may pair, which profiles are allowed, discoverability) and see an audit trail, without touching code |
| Multi-user | Each user's devices, audio choices and permissions stay separate; switching users never leaks a link or a key |
| Concurrency | 30 LE links, 7 Classic links, several audio streams, HID and scanning at the same time, with fair use of controller resources |
| Audio quality | No audible drift over a 3-hour stream; lip sync with video within 45 ms; glitch-free switching between devices |
| Supportability | A captured log can be decoded into readable text on the machine itself; every failure has a reason code |
| Lifecycle | Stable, versioned API; bond and settings data migrate across releases; a documented security-update process |

---

## 3. Target hardware

### Development machine

Read from the development machine's device list on 2026-11-04.

| Item | Value | Effect on the plan |
|---|---|---|
| Controller | MediaTek **RZ608** (MT7921 family), Wi-Fi 6E + Bluetooth **5.2** combo card | First and main target |
| Bus | USB, VID `0E8D` PID `0608`, interface 0 | Needs the USB stack and xHCI driver (Section 5) |
| Firmware | Needs a patch downloaded at every power-on through MediaTek vendor HCI commands | `vendor/mtk.asm`, Phase 1 |
| Highest version | 5.2 | Features from 5.3 to 6.3 can only be tested in `sim/` until a newer controller is bought |

### Peers the user already owns (from the paired device list)

These are the first interoperability targets. They say which profiles
matter first.

| Device | Kind | Profiles used |
|---|---|---|
| AirPods | Earbuds | A2DP (AAC preferred, SBC fallback), AVRCP, HFP |
| ONEPLUS 110BT (2 units), WS-887, DIGICOM K9, X100, F855 (2 units) | Headsets and speakers | A2DP (SBC), AVRCP, HFP/HSP |
| Galaxy A03 Core | Phone | PAN (NAP), OPP, PBAP, HFP Audio Gateway, SDP |

### Hardware to buy later (proposal, not decided)

| Item | Why |
|---|---|
| Nordic nRF52840 USB dongle with a standard HCI-over-USB controller firmware | Second USB controller from another vendor; a second radio for testing two hosts against each other; supports 5.4 features |
| Nordic nRF54L15 development kit as an HCI controller | Channel Sounding (6.0) and later features on real silicon |
| An Intel AX2xx card or USB adapter | Intel firmware loader (Phase 11) |
| A Realtek USB adapter | Realtek firmware loader (Phase 11) |
| An LE Audio earbud or hearing aid and an Auracast speaker | LE Audio interoperability (Phase 8) |
| A BLE keyboard and mouse, an older Classic-only keyboard | HID testing over both transports |

---

## 4. Key decisions

| # | Decision | Why |
|---|---|---|
| 1 | **Host only; the radio is always a controller chip** | Every real machine has a controller; a software radio is out of scope |
| 2 | **USB transport first, then UART (H4, H5), then SDIO** | The development machine's controller is on USB; most laptops and adapters use USB |
| 3 | **MediaTek first, other vendors in Phase 11** | That is the chip on the only machine |
| 4 | **Software controller (`sim/`) built alongside the host from day one** | Lets every feature from 1.0b to 6.3 be tested before hardware exists, and lets two hosts talk with no radio |
| 5 | Direct `call` API; events are delivered to a fiber per adapter | Same model as `lib/kvm`; no kernel/user boundary exists, so none is invented |
| 6 | One fiber per adapter runs the state machines; data paths (audio, HID) bypass it | Signalling stays simple and ordered; streaming stays low latency |
| 7 | **Audio codecs live in `lib/uaud`, not in `ubt`** | `ubt` moves encoded frames; SBC, mSBC, CVSD, LC3 and AAC are general audio code |
| 8 | **Math lives in `lib/umath`** | Direction-finding angle estimation and Channel Sounding distance estimation use umath (FFT, matrices, fixed point) |
| 9 | Crypto comes from `lib/crypto/ucrypt` | AES-128, AES-CMAC, AES-CCM, P-256 ECDH and HMAC-SHA-256 already exist there |
| 10 | Everything optional is gated on the controller's feature bits and the peer's features, read once and cached | One binary covers 1.1 to 6.3 controllers |
| 11 | `lib/unet/wireless/bluetooth.asm` (a 148-line stub) is retired | `ubt` replaces it; `unet` only receives IP packets from PAN/BNEP (Section 13) |

---

## 5. Dependencies

| Need | Where | State | Needed by |
|---|---|---|---|
| USB core (enumeration, descriptors, interfaces, alternate settings) | `lib/usb`, plan in `lib/usb/ROADMAP.md` | Planned | Phase 1 |
| xHCI host controller driver: control, bulk, interrupt **and isochronous** transfers | `lib/usb/hcd/xhci` | Planned (USB Phases 1–4) | Phase 1 (isochronous by Phase 5) |
| PCI, MSI-X, DMA, IOMMU | `lib/io/pci`, `lib/io/dma` | ◐ | xHCI |
| Wi-Fi driver for the RZ608 (same chip) | `lib/unet/drivers` (proposed) | **Not found** | Combo-chip reset coordination (Phase 1) |
| ACPI device lookup, GPIO pins, regulators, clocks | `lib/io/acpi` and a GPIO driver | ◐ ACPI only; GPIO **not found** | Phase 11 (serial and SDIO chips) |
| SDIO host controller driver | `lib/io` | **Not found** | Phase 11 |
| System sleep and resume, wake sources | `kernel/power` | ◐ | Phase 12 |
| UART driver with hardware flow control | `lib/io/char/serial.asm` | ◐ basic serial only | Phase 11 (H4/H5) |
| AES-128, AES-CMAC, AES-CCM | `lib/crypto/ucrypt` | ◐ | Phase 3 (SMP), Phase 7 (encrypted advertising), Phase 9 (Mesh) |
| P-256 ECDH | `lib/crypto/ucrypt/asymmetric/ecdh_p256.asm` | ◐ | Phase 3 (LE Secure Connections), Phase 9 |
| HMAC-SHA-256 | `lib/crypto/ucrypt/mac/hmac.asm` | ◐ | Phase 9 (Mesh 1.1 provisioning) |
| Random numbers | `lib/urand` | ◐ | Addresses, keys, nonces |
| Audio codecs: SBC, mSBC, CVSD, LC3, AAC | `lib/uaud` | **Empty** | Phase 5, Phase 8 |
| Audio mixing and devices | `lib/uaud` | **Empty** | Phase 5 |
| Input events and the shared HID parser | `lib/input` (plan in `lib/input/ROADMAP.md`) | Planned | Phase 4 |
| Encrypted key storage | `/sec/keys/` via `security/usrauth` | ◐ | Phase 2 |
| FFT, complex numbers, matrices | `lib/umath` | ◐ | Phase 7 (direction finding), Phase 10 |

USB and xHCI block everything on real hardware. Until they exist, all work
runs against `sim/` through the in-memory transport.

---

## 6. Feature map: every Core version

Columns: **Controller** is what the chip does, **Host work** is what `ubt`
builds, **Module** is where, **Phase** is when, **RZ608** says whether the
development controller can test it.

### 6.1 Classic era (BR/EDR)

| Version | Year | Controller features | Host work in `ubt` | Module | Phase | RZ608 |
|---|---|---|---|---|---|---|
| **1.0b** | 1999 | Basic Rate radio, baseband, LMP, E0 encryption | HCI commands/events/ACL/SCO; inquiry, page, remote name; L2CAP basic mode; SDP; PIN (legacy) pairing events; link key storage | `hci/`, `gap/br/`, `l2cap/`, `sdp/`, `sm/br/` | 1–2 | ✓ |
| **1.1** | 2001 | Fixes, unencrypted channels | Interoperate with 1.1 peers; RSSI read | `gap/br/` | 2 | ✓ |
| **1.2** | 2003 | AFH, eSCO, faster connection, inquiry with RSSI | eSCO setup and negotiation; L2CAP flow control and retransmission modes; inquiry-with-RSSI results | `hci/sco`, `l2cap/` | 2, 5 | ✓ |
| **2.0 + EDR** | 2004 | 2 and 3 Mbit/s EDR packets | Packet-type masks for ACL and eSCO | `hci/`, `gap/br/` | 2 | ✓ |
| **2.1 + EDR** | 2007 | Secure Simple Pairing (P-192 in the controller), sniff subrating, encryption pause/resume, link supervision events | SSP: IO capabilities, numeric comparison, passkey, Just Works, OOB; Extended Inquiry Response (EIR) build and parse; sniff subrating policy | `sm/br/`, `gap/br/` | 2 | ✓ |
| **3.0 + HS** | 2009 | AMP (802.11 data), enhanced power control | **Enhanced Retransmission Mode, Streaming Mode**, FCS, unicast connectionless data. **AMP not built** (withdrawn in 5.3) | `l2cap/ertm` | 6 | ✓ |

### 6.2 LE arrives (4.x)

| Version | Year | Controller features | Host work in `ubt` | Module | Phase | RZ608 |
|---|---|---|---|---|---|---|
| **4.0** | 2010 | Low Energy radio and link layer | LE HCI; legacy advertising and scanning; LE connections; ATT; GATT client and server; **SMP legacy pairing** (host computes c1, s1 with AES-128); LE signaling channel; privacy 1.0 (host resolves random addresses with `ah`); dual-mode GAP | `gap/le/`, `att/`, `gatt/`, `sm/le/` | 3 | ✓ |
| **4.1** | 2013 | LE dual role, LE ping, connection parameter request, BR/EDR Secure Connections (P-256, AES-CCM) | **L2CAP LE credit-based channels**; connection parameter negotiation; BR/EDR Secure Connections and Secure Connections Only mode; authenticated payload timeout; train nudging aware | `l2cap/le_coc`, `sm/br/` | 3, 2 | ✓ |
| **4.2** | 2014 | LE Data Length Extension, LL privacy (resolving list), extended scanner filter | **LE Secure Connections** (P-256 ECDH; f4, f5, f6, g2 with AES-CMAC); cross-transport key derivation (h6, h7) with safe rules; data length negotiation; resolving list management; privacy 1.2 | `sm/le/`, `sm/ctkd`, `gap/le/privacy` | 3 | ✓ |

### 6.3 Bluetooth 5

| Version | Year | Controller features | Host work in `ubt` | Module | Phase | RZ608 |
|---|---|---|---|---|---|---|
| **5.0** | 2016 | LE 2M PHY, LE Coded PHY (long range), extended advertising, periodic advertising, channel selection #2, slot availability mask | PHY selection policy; extended advertising sets (build, chain, rotate); extended scanning; periodic advertising source and sync | `gap/le/adv`, `gap/le/scan`, `gap/le/periodic` | 7 | ✓ |
| **5.1** | 2019 | Direction finding (AoA/AoD, CTE, IQ sampling), randomized advertising channel index, periodic advertising sync transfer (PAST) | **GATT caching** (Database Hash, Client Supported Features, robust caching); PAST sender and receiver; CTE enable, antenna switching patterns, IQ report collection; angle estimation using umath | `gatt/cache`, `gap/le/past`, `df/` | 7 | partial (no antenna array) |
| **5.2** | 2019 | **LE isochronous channels** (CIS, BIS), LE power control, ISO adaptation layer | **EATT** (ATT over L2CAP enhanced credit-based mode); **L2CAP enhanced credit-based channels**; ISO data path: CIG/CIS, BIG/BIS, SDU timing, ISO over HCI; power control reports; foundation for LE Audio | `att/eatt`, `l2cap/ecred`, `iso/` | 7, 8 | ✓ (ISO support to be confirmed on the chip) |
| **5.3** | 2021 | Connection subrating, periodic advertising ADI, channel classification enhancement, encryption key size control; AMP removed | Subrating policy; ADI in periodic advertising; set **minimum key size to 16 in the controller** where supported | `gap/le/conn`, `sm/` | 7 | sim only |
| **5.4** | 2023 | **Periodic Advertising with Responses (PAwR)**, advertising coding selection | **Encrypted Advertising Data** (AES-CCM, Key Material characteristic); LE GATT Security Levels characteristic; PAwR broadcaster and observer (electronic shelf labels and similar) | `gap/le/pawr`, `gap/le/ead`, `gatt/` | 7 | sim only |

### 6.4 Bluetooth 6

| Version | Year | Controller features | Host work in `ubt` | Module | Phase | RZ608 |
|---|---|---|---|---|---|---|
| **6.0** | 2024 | **Channel Sounding** (phase-based ranging and round-trip timing), decision-based advertising filtering, monitoring advertisers, ISOAL enhancement, LL extended feature set, frame space update | CS capability exchange, configuration, security setup, procedure scheduling, result collection; **distance estimation** (phase slope, RTT) using umath; Ranging Profile and Ranging Service (RAP/RAS); decision data in advertising; monitored-advertiser lists; extended feature pages; frame space negotiation | `cs/`, `gap/le/` | 10 | sim only |
| **6.1** | 2025 | Randomized timing of RPA updates done by the controller | Hand RPA rotation timing to the controller when supported; keep host rotation as fallback | `gap/le/privacy` | 10 | sim only |
| **6.2** | 2025 | **Shorter connection intervals** (down to 375 µs), CS amplitude-based attack resilience, Unified Test Protocol | Short-interval policy for HID and gaming peers; CS attack-resilience checks in distance results; **USB bulk serialization mode for ISO data**; UTP for factory and lab tests | `gap/le/conn`, `cs/`, `tr/usb`, `test/` | 10 | sim only |
| **6.3** | 2026 | Inline PCT transfer for Channel Sounding, PHY-specific RTT accuracy, larger HCI command and event masks, RF limit alignment (no host work) | Inline PCT result path; per-PHY RTT accuracy in distance confidence; **wide Supported Commands and LE Event Mask** handling | `cs/`, `hci/mask` | 10 | sim only |

### 6.5 Smaller items from each version

These have no phase of their own, so they are listed here to make sure
nothing is dropped.

| Version | Item | Host work | Phase |
|---|---|---|---|
| 1.0b–1.2 | Hold mode, park mode (park removed in later versions; peers may still ask) | Accept or refuse peer requests; never start park | 2 |
| 1.2 | QoS, flow specification, flush timeout, automatic flush | Set per channel for audio; flushable and non-flushable ACL | 2, 5 |
| 2.1 | Erroneous data reporting, enhanced flush | Used by eSCO audio for packet-loss concealment | 5 |
| 4.0 | Read and write LE host support, LE white list sizes | Respect the controller's list sizes; fall back to host filtering when full | 3 |
| 4.1 | **Connectionless Slave Broadcast and synchronization train** (used by 3D glasses and some broadcast accessories) | Transmitter and receiver | 6 |
| 4.1 | **MWS coexistence signalling** (LTE and 5G modems) | Pass the modem's channel map to the controller when the platform has a modem | 11 |
| 4.1 | LE ping, authenticated payload timeout | Set timeouts; handle the expiry event | 3 |
| 5.3 | **HCI codec commands**: read local supported codecs (v2), codec capabilities, controller delay, configure data path | Choose host or offloaded codec per stream | 5, 8 |
| All | **RF test modes**: device under test mode (Classic), Direct Test Mode (LE) | Lab and regulatory tests; admin only | 12 |

New Core releases arrive about twice a year. Each one gets a row here, an
HCI table update, and a `sim/` update before any host work.

---

## 7. Architecture

```
          ush `bt`   canvas Settings → Bluetooth   uaud   input   unet
              │                │                     │      │       │
 ┌────────────┴────────────────┴─────────────────────┴──────┴───────┴──────┐
 │ api/        adapters, devices, pairing, profiles, events                 │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ prof/br/  A2DP AVRCP HFP HSP HID PAN SPP OPP FTP PBAP MAP DI             │
 │ prof/le/  HOGP BAS DIS SCPS · LE Audio (BAP CAP VCP MCP CCP CSIP HAP     │
 │           TMAP PBP GMAP) · RAP · ESL                                     │
 │ mesh/     bearers, network, transport, access, provisioning, models      │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ avdtp avctp rfcomm obex bnep │ att/eatt gatt │ iso │ cs │ df             │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ sdp │ sm/br sm/le sm/ctkd keys │ l2cap (basic ertm stream le_coc ecred)  │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ gap/br (inquiry page names eir)  gap/le (adv scan conn privacy periodic) │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ hci/  commands events acl sco iso · flow control · feature cache · masks │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ vendor/ mtk intel rtl bcm qca nordic    │ snoop/ packet capture          │
 ├──────────────────────────────────────────────────────────────────────────┤
 │ tr/ usb (H2) │ h4 │ h5 │ sdio │ mem (in-memory, to sim/)                 │
 └──────────────────────────────────────────────────────────────────────────┘
        │                 │                      │
     lib/usb           serial               sim/ software controller
```

### 7.0 Driver and platform layer

This layer sits under HCI and is what makes a real chip work. It is spread
over Phases 1, 11 and 12.

| Need | What it means | Module | Phase |
|---|---|---|---|
| **Transports** | USB; UART (H4, H5 three-wire, BCSP for old CSR chips); SDIO; **PCIe** (newer Intel integrated parts and Broadcom chips on PCIe use their own ring-buffer interfaces); **virtio** (Bluetooth for virtual machines) | `tr/` | 1, 11 |
| **Platform setup** | Find UART and SDIO chips through ACPI; drive their power-enable, reset, host-wake and device-wake pins; switch on regulators and clocks; set baud rate after firmware load | `plat/` | 11 |
| **Firmware** | Patch download per vendor; per-board configuration files (Realtek config, Broadcom board files, Intel DDC); check version before and after; retry, then report failure clearly; never leave a half-loaded chip | `vendor/` | 1, 11 |
| **Vendors** | MediaTek (USB, SDIO, UART), Intel (USB, PCIe), Realtek, Broadcom (USB, UART, PCIe), Qualcomm (USB, UART with power sequencing), NXP, Marvell, TI, Atheros, CSR, Nordic and other standard controllers | `vendor/` | 1, 11 |
| **Combo chips** | Wi-Fi and Bluetooth on one chip (the RZ608 is one): coordinate resets and firmware crashes with the Wi-Fi driver; whole-chip reset when needed; firmware-level coexistence settings | `vendor/`, shared with the Wi-Fi driver | 1, 11 |
| **Device address** | Chips with no public address or a placeholder address: set one by vendor command, or use a stable static random address stored in `/conf/bt/` | `hci/`, `vendor/` | 1 |
| **Recovery and diagnostics** | Hardware-error and vendor events; collect firmware crash dumps to `/keep/dump/bt/`; read vendor debug and trace channels; command timeout watchdog; reset and replay of state | `vendor/`, `hci/` | 1, 12 |
| **Quirks** | A table per chip and firmware version of broken commands, wrong feature bits and missing features | `vendor/quirks` | 11 |
| **Power management** | USB autosuspend and remote wake; system sleep and resume with links restored; **wake on Bluetooth** (keyboard or mouse wakes the machine); runtime power-off when no device is in use | `pm/` | 4, 12 |
| **Radio kill** | Airplane mode, hardware kill switch and key; per-radio software switch; state in `/sys/dev/bt0/` | `pm/` | 1 |
| **Vendor HCI extensions** | Two widely used extension sets: advertisement-monitor offload, multi-advertising, offloaded scan filtering, energy reporting; used when the chip reports them | `hci/ext` | 7 |
| **Audio offload** | Route SCO over the chip's PCM/I2S pins to the sound codec instead of HCI (common on laptops); offloaded LE Audio and A2DP data paths; coordinate with `uaud` | `hci/`, `vendor/` | 5, 8 |

### 7.1 Folder layout

```
lib/ubt/
├── ROADMAP.md
├── README.md
├── ubt.inc               public structures and constants
├── ubt.asm               entry points, adapter list
├── api/                  adapter, device, pairing, profile and event API
├── tr/                   usb.asm h4.asm h5.asm bcsp.asm sdio.asm pcie/
│                         virtio.asm mem.asm
├── plat/                 ACPI lookup, power and wake pins, regulators, clocks
├── pm/                   suspend, resume, wake on Bluetooth, radio kill
├── vendor/               mtk.asm intel.asm rtl.asm bcm.asm qca.asm nxp.asm
│                         mrvl.asm ti.asm ath.asm csr.asm nordic.asm quirks.asm
├── hci/                  cmd.asm evt.asm acl.asm sco.asm iso.asm flow.asm
│                         feat.asm (version and feature cache) mask.asm tables/
├── gap/
│   ├── br/               inquiry.asm page.asm name.asm eir.asm mode.asm
│   └── le/               adv.asm scan.asm conn.asm privacy.asm periodic.asm
│                         past.asm pawr.asm ead.asm phy.asm subrate.asm
├── l2cap/                core.asm sig.asm basic.asm ertm.asm stream.asm
│                         le_coc.asm ecred.asm fixed.asm
├── sm/
│   ├── br/               ssp.asm legacy.asm sc.asm
│   ├── le/               smp.asm legacy.asm sc.asm crypto.asm
│   ├── ctkd.asm
│   └── keys.asm          bonding store in /sec/keys/bt/
├── sdp/                  server.asm client.asm de.asm (data elements)
├── att/                  att.asm eatt.asm
├── gatt/                 server.asm client.asm db.asm cache.asm svc/
├── avdtp/  avctp/  rfcomm/  obex/  bnep/
├── iso/                  cig.asm big.asm path.asm sync.asm
├── prof/
│   ├── br/               a2dp/ avrcp/ hfp/ hsp/ hid/ pan/ spp/ opp/ ftp/
│   │                     pbap/ map/ did/
│   └── le/               hogp/ bas/ dis/ scps/ audio/ rap/ esl/
├── mesh/                 bearer/ net/ transport/ access/ prov/ models/
│                         df/ (directed forwarding) dfu/ rpr/ (remote prov)
├── cs/                   Channel Sounding host side and distance estimation
├── df/                   direction finding: CTE control, IQ handling, angles
├── dev/                  device database, connection manager, interop database
├── res/                  controller resource manager, app scanning, limits
├── mgmt/                 policy, permissions, multi-user, audit, migration,
│                         statistics
├── tools/                `bt` command back end, protocol decoder, monitor
├── snoop/                packet capture in a standard capture file format
├── sim/                  software controller and virtual radio (tests only)
└── tests/
```

### 7.2 Where data lives (fits the frozen root layout)

| Data | Path | Notes |
|---|---|---|
| Adapter settings (name, class, discoverable timeout, policies) | `/conf/bt/` | Admin-write |
| Bond keys (link keys, LTK, IRK, CSRK), per adapter and peer | `/sec/keys/bt/<adapter>/<peer>` | Admin-only, encrypted |
| Paired device list and cached GATT databases, SDP records | `/data/ubt/` | Disk |
| Controller firmware patches | `/app/lib/ubt/fw/<vendor>/` | Read-only, signed by the build |
| Live state: adapters, links, channels, counters | `/sys/dev/bt0/` | Virtual |
| Packet captures | `/keep/log/sys/bt/` | Only when enabled |
| Per-user choices (default audio device, auto-connect) | `/user/<name>/conf/bt` | Owner-only |

### 7.3 API shape

- `ubt_adapter_open(index) → adapter`, `ubt_adapter_power(adapter, on)`
- `ubt_discover_start(adapter, flags)` with flags for BR inquiry, LE scan,
  both; results arrive as `UBT_EV_FOUND` events
- `ubt_pair(adapter, addr, policy)`; prompts arrive as `UBT_EV_CONFIRM`,
  `UBT_EV_PASSKEY`, `UBT_EV_PIN`, answered by `ubt_pair_reply`
- `ubt_connect(adapter, addr, profile_mask)`, `ubt_disconnect`
- GATT: `ubt_gatt_discover`, `ubt_gatt_read`, `ubt_gatt_write`,
  `ubt_gatt_subscribe`, `ubt_gatt_service_add` (server)
- L2CAP sockets for profiles and apps: `ubt_l2_listen`, `ubt_l2_connect`,
  `ubt_l2_send`, `ubt_l2_recv`
- Streams: `ubt_stream_open` returns a ring of encoded frames shared with
  `uaud` (A2DP, HFP, LE Audio); no copies on the data path
- Events: each client gets a ring of fixed-size event records, read from
  its own fiber

All structures are versioned so saved bond data stays loadable after
upgrades.

### 7.4 Management, operations and app layer

These parts make the protocol stack usable and manageable across a fleet of
machines. They live in `mgmt/`, `dev/`, `res/` and `tools/`.

| Area | What it covers | Module | Phase |
|---|---|---|---|
| **Device database** | One record per peer: identity address, names, class, appearance, services, bond state, last seen. Merges a dual-mode device seen over Classic and LE into one record. Resolves random addresses to identities | `dev/` | 2, 3 |
| **Connection manager** | Auto-reconnect rules per device and profile; connection priority; profile ordering (HFP before A2DP and so on); recovery after link loss; multipoint headsets shared with a phone | `dev/conn` | 5 |
| **Controller resource manager** | Shares limited controller resources between clients: connections, advertising sets, accept list and resolving list entries, ISO streams, scan time. Falls back to host-side work when the controller runs out | `res/` | 3, 7 |
| **Scanning for apps** | Per-app scan filters, batched results, background scanning with a power budget, advertisement monitors (offloaded when the chip can) | `res/scan` | 7 |
| **Admin policy** | `/conf/bt/policy`: allowed and blocked service UUIDs and device classes, allowed profiles (for example no file transfer), Secure Connections only, discoverability rules, allowed devices list, minimum security level per profile | `mgmt/policy` | 13 |
| **Permissions** | Uses the OS capability model (`security/usrauth`): which users may pair, which apps may use raw HCI, raw L2CAP, GATT server, advertising, background scanning | `mgmt/caps` | 13 |
| **Multi-user** | Bonds are per machine; device ownership and visibility per user (personal earbuds stay with their owner); audio and input routed to the active user only; links handed over or dropped on user switch | `mgmt/user` | 13 |
| **Audit log** | Pairing, unpairing, policy refusals, new devices, firmware loads and security failures written to `/keep/log/sec/bt` | `mgmt/audit` | 13 |
| **Backup and migration** | Bonds and settings covered by the OS backups (`conf`, `sec`, `data`); versioned formats with upgrade steps; export and import of a device between machines (admin only) | `mgmt/` | 13 |
| **Peer interop database** | Workarounds for specific peers by address prefix, name and version: broken SDP records, wrong codec capabilities, reconnection quirks, volume handling | `dev/interop` | 5, 12 |
| **Abuse protection** | Rate limits on pairing attempts, incoming connections, L2CAP channel requests and GATT requests; caps on memory used by advertising floods and device-database growth; pairing-request spam blocking | `res/limits` | 3, 12 |
| **Tracker detection** | Detects unknown location trackers travelling with the user (Unwanted Location Tracker Detection rules) and alerts | `prof/le/dult` | 13 |
| **Audio timing** | Jitter buffers, clock drift compensation between the audio clock and each peer, delay reporting to `uvid` for lip sync, seamless switching between output devices | `avdtp/`, `iso/`, with `uaud` | 5, 8 |
| **Tools** | `bt` command: devices, pair, connect, info, GATT browse and read/write, L2CAP ping, raw HCI (admin only), live monitor; a protocol decoder that turns captures into readable text | `tools/` | 1 onward |
| **Metrics** | Per-link RSSI, packet errors, retransmits, audio underruns, reconnect counts, exported through `/sys/dev/bt0/` and `lib/obs` | `mgmt/stats` | 1 onward |
| **Documentation** | API reference for app authors, administrator guide, troubleshooting guide with reason codes | `docs/` | 13 |

---

## 8. Phases

Each phase ends with a demo on `sim/`, and on the RZ608 from Phase 1
onward once USB exists. A phase is done when its tests pass, its parsers
have been fuzzed for 24 hours with no findings, and its counters show in
`/sys/dev/bt0/`.

### Phase 0 — Foundations (no hardware)

- ☐ `ubt.inc`: adapter, connection, channel, buffer and event structures
- ☐ `tr/mem.asm`: in-memory H4 transport
- ☐ `sim/` step 1: a BR/EDR + LE controller model that answers the HCI
  commands of 1.0b to 4.2, with a virtual radio connecting any number of
  simulated controllers, adjustable loss, delay and noise
- ☐ `snoop/`: capture every HCI packet with time stamps, in a standard
  capture file format that common protocol analysers can open
- ☐ HCI tables generated from one source file: every opcode, event code,
  parameter layout and minimum version from 1.0b to 6.3
- ☐ Test harness: scripted scenarios (two or more hosts on `sim/`), and a
  fuzzer that feeds every parser

Estimate: ~9 000 lines (most of it in `sim/`).

### Phase 1 — Controller bring-up (`bt0` comes up)

Prerequisite: `lib/usb` with xHCI control, bulk and interrupt transfers.

- ☐ `tr/usb.asm`: match by the Bluetooth USB class (E0/01/01) and by a
  vendor ID table; interrupt endpoint for events, bulk for ACL, control for
  commands, isochronous interface for SCO (Phase 5)
- ☐ `vendor/mtk.asm`: MediaTek firmware download through vendor HCI
  commands, patch semaphore, power on and off, reset recovery. Firmware file
  from MediaTek's redistributable package, stored in `/app/lib/ubt/fw/mtk/`
- ☐ HCI core: command queue with the controller's credit count, command
  timeouts, event dispatch, ACL fragmentation and reassembly, host flow
  control, buffer size reads (BR and LE)
- ☐ Init sequence: reset → read local version → supported commands →
  features (all pages) → buffer sizes → BD_ADDR → set event masks → LE
  init when LE is supported
- ☐ Hot unplug and replug, controller hardware error event, automatic
  re-initialisation
- ☐ `/sys/dev/bt0/`: version, manufacturer, features, counters
- ☐ `ush`: `bt show`, `bt power on|off`

Demo: `bt show` prints "MediaTek, HCI 5.2" and the address of the RZ608.
Estimate: ~5 500 lines.

### Phase 2 — Classic core (1.0b to 2.1, 4.1 Secure Connections)

- ☐ Inquiry (standard, with RSSI, extended), remote name, EIR parse and
  build, page and page scan, connectable and discoverable modes, class of
  device
- ☐ ACL connection handling, role switch, sniff mode and subrating policy,
  link supervision
- ☐ L2CAP basic mode: signaling, configuration, MTU, fixed and dynamic
  channels, echo, information requests
- ☐ SDP server and client: data elements, service search, attribute
  search, continuation states
- ☐ Pairing: SSP (all four models), Secure Connections and Secure
  Connections Only mode, legacy PIN pairing for pre-2.1 peers (decision D3)
- ☐ Bond store in `/sec/keys/bt/`, authentication and encryption, key
  refresh, minimum key size checks
- ☐ `ush`: `bt scan`, `bt pair`, `bt devices`, `bt forget`

Demo: pair the Galaxy phone and browse its SDP records.
Estimate: ~11 000 lines.

### Phase 3 — LE core (4.0 to 4.2)

- ☐ Legacy advertising and scanning, active and passive, filter accept
  list
- ☐ LE connections, connection parameter update (both ways), data length
  extension
- ☐ L2CAP LE signaling, LE credit-based channels
- ☐ ATT (all PDUs, MTU exchange, prepared writes, signed writes)
- ☐ GATT server (database, permissions, notifications, indications,
  service changed) and client (discovery, read, write, long values,
  subscribe)
- ☐ SMP: legacy and Secure Connections pairing, all association models,
  bonding, key distribution, IRK and address resolution, signing keys
- ☐ Cross-transport key derivation with the rules from the BLURtooth fixes
- ☐ Privacy: resolvable private addresses, rotation, controller resolving
  list
- ☐ Built-in services: GAP, GATT, Device Information, Battery

Demo: connect to a BLE peripheral, read its battery level, pair with
Secure Connections.
Estimate: ~12 000 lines.

### Phase 4 — Input devices

- ☐ Classic HID host: control and interrupt channels, boot and report
  protocols, reconnection; reports parsed by the shared HID core in
  `lib/input/hid`
- ☐ HID over GATT (HOGP) host, Scan Parameters service
- ☐ Delivery to the canvas input queue with the latency target from
  Section 2
- ☐ Keyboard pairing with passkey display
- ☐ HID device role (the machine acting as a keyboard) — later

Demo: type and move the pointer with Bluetooth keyboards and mice on both
transports.
Estimate: ~5 000 lines.

### Phase 5 — Classic audio

Prerequisite: xHCI isochronous transfers for SCO; `lib/uaud` with SBC,
mSBC, CVSD (and AAC, decision D1).

- ☐ AVDTP: discovery, capabilities, configuration, delay reporting,
  streaming channel, media packet timing
- ☐ A2DP source and sink: SBC (mandatory), AAC (decision D1); bitpool and
  rate adaptation; the user's AirPods prefer AAC
- ☐ AVCTP and AVRCP 1.6 controller and target: play, pause, skip, absolute
  volume, metadata, browsing, cover art (over OBEX/BIP, after Phase 6)
- ☐ SCO and eSCO over USB isochronous endpoints, with the right alternate
  setting per codec
- ☐ HFP 1.9 hands-free and audio gateway roles, HSP; CVSD, mSBC and LC3-SWB
  (super wideband speech)
- ☐ SCO routed over PCM/I2S to the sound codec where the laptop is wired
  that way
- ☐ Battery levels from headsets: HFP indicators, plus the extra AT
  commands used by AirPods and many other headsets
- ☐ Audio device switching with `uaud`, reconnect on boot

Demo: music to the ONEPLUS 110BT and the AirPods, a call through the
Galaxy phone with the microphone working.
Estimate: ~13 000 lines (not counting codecs).

### Phase 6 — Classic data and phone profiles

- ☐ L2CAP Enhanced Retransmission Mode and Streaming Mode (3.0)
- ☐ RFCOMM (multiplexer, credit flow control, remote port negotiation)
- ☐ SPP
- ☐ OBEX over RFCOMM and over L2CAP, GOEP 2.x, SRM
- ☐ OPP (send and receive files), FTP, PBAP client, MAP client, BIP for
  AVRCP cover art
- ☐ BNEP and PAN (PANU first; NAP and GN later), handing IP packets to
  `unet`
- ☐ Device ID (DI) record

Demo: receive a photo from the phone, download its contacts, use its
internet connection through PAN.
Estimate: ~12 000 lines.

### Phase 7 — LE 5.x features (5.0 to 5.4)

- ☐ Extended advertising: multiple sets, chaining, scan responses,
  periodic advertising source and sync, PAST
- ☐ PHY policy: 1M, 2M, Coded S=2 and S=8
- ☐ EATT and L2CAP enhanced credit-based channels
- ☐ GATT caching and robust caching
- ☐ LE power control, connection subrating, channel classification
- ☐ PAwR, encrypted advertising data, GATT security levels characteristic
- ☐ Direction finding: CTE request and response, IQ reports, angle of
  arrival and departure estimation with umath (needs an antenna array;
  `sim/` until then)
- ☐ `sim/` step 2: the 5.0 to 5.4 link layer features

Estimate: ~12 000 lines.

### Phase 8 — LE Audio and Auracast

Prerequisite: `lib/uaud` with LC3. A controller with ISO support (confirm
on the RZ608; otherwise a newer controller).

- ☐ ISO: CIG and CIS setup, BIG create and sync, ISO data path over HCI,
  SDU timing, presentation delay
- ☐ BAP (unicast client and server, broadcast source, sink and assistant),
  PACS, ASCS, BASS
- ☐ CAP (coordinated sets, handover), CSIP/CSIS (earbud pairs)
- ☐ VCP with VOCS and AICS, MICP
- ☐ MCP/GMCS (media control), CCP/TBS (calls)
- ☐ HAP/HAS (hearing aids), TMAP, PBP (public broadcasts), GMAP (gaming)
- ☐ Auracast: receive a public broadcast, act as a broadcast source and
  assistant
- ☐ `sim/` step 3: ISO in the virtual radio

Estimate: ~18 000 lines.

### Phase 9 — Mesh 1.1

- ☐ Advertising and GATT bearers, proxy
- ☐ Network layer (relay, friend, low power, heartbeat), upper and lower
  transport, segmentation
- ☐ Access layer, foundation models (configuration, health)
- ☐ Provisioning (provisioner and device), certificate-based provisioning,
  remote provisioning
- ☐ Directed forwarding, subnet bridge, private beacons
- ☐ Firmware update (DFU) models, BLOB transfer
- ☐ Common models: generic, lighting, sensors, time and scenes
- ☐ Key storage in `/sec/keys/bt/mesh/`

Estimate: ~20 000 lines.

### Phase 10 — Bluetooth 6.x

Prerequisite: a 6.x controller (Section 3) for real-radio tests.

- ☐ Channel Sounding: capabilities, configuration, security, procedure
  scheduling, step results, inline PCT transfer (6.3)
- ☐ Distance estimation: phase-based ranging and RTT with confidence,
  per-PHY RTT accuracy (6.3), amplitude-based attack checks (6.2); math in
  umath
- ☐ Ranging Profile and Ranging Service (RAP/RAS)
- ☐ Decision-based advertising filtering, monitoring advertisers, LL
  extended features, frame space update (6.0)
- ☐ Controller-timed RPA updates (6.1)
- ☐ Shorter connection intervals for HID and gaming (6.2)
- ☐ USB bulk serialization for ISO data (6.2), Unified Test Protocol (6.2)
- ☐ Wide command and event masks (6.3)
- ☐ `sim/` step 4: 6.0 to 6.3 link layer features

Estimate: ~10 000 lines.

### Phase 11 — More controllers and transports

- ☐ Firmware loaders: Intel, Realtek, Broadcom, Qualcomm, NXP, Marvell, TI,
  Atheros, CSR; standard controllers such as Nordic need none
- ☐ H4 over UART (with hardware flow control), H5 (three-wire, with
  reliable transport and low power), BCSP, SDIO, PCIe (Intel and
  Broadcom), virtio
- ☐ Platform setup from ACPI: pins, regulators, clocks, baud rate
- ☐ MWS coexistence signalling with cellular modems
- ☐ Several adapters at once
- ☐ Vendor quirk table (broken commands, wrong feature bits)

Estimate: ~6 000 lines.

### Phase 12 — Hardening and release

- ☐ Conformance suites for each protocol and profile, built from the
  Bluetooth SIG test specifications, run against `sim/` on every build
- ☐ Fuzzing: HCI events, L2CAP, SDP, ATT, SMP, AVDTP, RFCOMM, OBEX, BNEP,
  Mesh, all advertising data parsers
- ☐ Interop matrix: every device in Section 3, run before each release
- ☐ 72-hour soak test on real hardware
- ☐ Power: sniff and subrating policies, LE connection intervals tuned to
  battery and latency needs
- ☐ Sleep and resume with links restored; wake on Bluetooth; USB
  autosuspend
- ☐ Fault injection: firmware crash, stuck command, USB reset mid-transfer,
  Wi-Fi-side reset of a combo chip
- ☐ Crash dump collection and vendor trace channels
- ☐ RF test modes (device under test mode, Direct Test Mode, Unified Test
  Protocol)
- ☐ Quick pairing: a pop-up when a known kind of device in pairing mode is
  nearby (decision D8)
- ☐ Qualification and listing (decision D5)

### Phase 13 — Enterprise management

- ☐ Admin policy file and Settings page, applied live
- ☐ Capability checks for every API that touches the radio
- ☐ Multi-user device ownership and routing; behaviour on user switch
- ☐ Audit log of pairing, policy and security events
- ☐ Bond and settings migration between releases; export and import
- ☐ Unwanted tracker detection
- ☐ Administrator guide, API reference, troubleshooting guide
- ☐ Security-update process: how a fix for a Bluetooth flaw or a new
  firmware file reaches machines, and how fast

Estimate: ~6 000 lines.

---

## 9. Profile and service list

### Built

| Area | Profiles and services |
|---|---|
| Classic core | GAP, SDP, L2CAP (all modes), RFCOMM, OBEX/GOEP, DI |
| Classic audio | A2DP 1.4, AVDTP 1.3, AVRCP 1.6.2, AVCTP, HFP 1.9, HSP 1.2 |
| Classic input | HID 1.1 (host, then device) |
| Classic data | SPP, PAN/BNEP, OPP, FTP, PBAP, MAP, BIP (for cover art) |
| LE core | GAP, GATT, ATT, EATT, SMP, Battery, Device Information, Scan Parameters, HOGP |
| LE Audio | BAP, PACS, ASCS, BASS, CAP, CSIP/CSIS, VCP, VOCS, AICS, MICP, MCP/GMCS, CCP/TBS, HAP/HAS, TMAP, PBP, GMAP |
| Other LE | ESL (electronic shelf labels over PAwR), RAP/RAS (ranging), OTS (Object Transfer, needed by full MCP), generic GATT client for any other service |
| LE for wearables and accessories | Current Time, Alert Notification, Phone Alert Status, Immediate Alert, Link Loss, TX Power (find-me and proximity), so watches and tags can sync with the machine |
| IP over LE | IPSP with 6LoWPAN header compression, handing IPv6 packets to `unet` (IoT gateways) |
| Safety | Unwanted location tracker detection |
| Mesh | Mesh Protocol 1.1, Mesh Model 1.1 |

### Not built

Deprecated or withdrawn: AMP, HDP, BPP, SAP, CTP, ICP, FAX, HCRP, DUN, VDP,
GAVDP-only uses, SYNC. Health and fitness GATT services (heart rate,
glucose and others) are not built into `ubt`; apps use the generic GATT
client.

---

## 10. Testing

| Level | How |
|---|---|
| Unit | Each encoder and parser against the sample data in the specifications (SMP, Mesh and LE Audio sample data have exact test vectors) |
| Protocol | Two or more `ubt` hosts on `sim/`, scripted, for every procedure and every version |
| Version matrix | `sim/` set to report each Core version from 1.1 to 6.3; the same scenarios run against each, so every feature gate is checked |
| Fuzz | Every parser, every phase; crashes and hangs fail the build |
| Hardware | The RZ608 against the devices in Section 3; later the controllers from Section 3 |
| Soak | 72 hours of audio, HID and LE traffic |

QEMU has no Bluetooth device, so hardware tests run on bare metal, or in
`apps/uvm` with USB passthrough once that exists.

Note: QEMU runs are paused on the development machine; host test suites
against `sim/` are allowed.

---

## 11. Rough size

| Part | Lines (±50%) |
|---|---|
| Transports, vendor loaders, platform, power, quirks | 12 000 |
| HCI | 6 000 |
| GAP (BR and LE) | 9 000 |
| L2CAP | 6 000 |
| Security (SM, keys, CTKD) | 7 000 |
| SDP, ATT/GATT, EATT | 8 000 |
| RFCOMM, OBEX, BNEP, AVDTP, AVCTP | 8 000 |
| Classic profiles | 15 000 |
| ISO + LE Audio | 18 000 |
| Mesh | 20 000 |
| Channel Sounding + direction finding | 9 000 |
| `sim/` software controller | 22 000 |
| Device database, connection and resource managers, interop database | 7 000 |
| Management: policy, permissions, multi-user, audit, migration | 6 000 |
| Tools: `bt` back end, protocol decoder, monitor | 5 000 |
| Extra LE profiles (wearables, OTS, IPSP, tracker detection) | 4 000 |
| **Total** | **~162 000** |

Codecs in `lib/uaud` are extra: SBC and mSBC ~3 000, CVSD ~500, LC3
~10 000, AAC ~15 000.

---

## 12. Security

| Threat | Fix in `ubt` |
|---|---|
| Malformed packets from the air or the controller (the BlueBorne class) | Length-checked parsers only; fuzzing; no recursion on input; fixed limits on every queue |
| Key size downgrade (KNOB) | Reject encryption keys shorter than 16 bytes; use 5.3 key size control when present |
| Impersonation during reconnection (BIAS) | Secure Connections required for bonded reconnects; mutual authentication; no role-switch shortcut |
| Cross-transport key overwrite (BLURtooth) | Never let CTKD replace a stronger key or an authenticated key with a weaker one |
| Weak session keys (BLUFFS) | Secure Connections Only mode by default where peers allow it; check session key freshness |
| Pairing downgrade | Never fall back from Secure Connections to legacy without user action; show the pairing method |
| Tracking | Resolvable private addresses by default for LE; rotate at least every 15 minutes |
| Malicious controller firmware | Firmware files are signed by the build and checked before download |
| Data from an untrusted peer reaching other libraries | Profiles pass bounded, already-checked data only |

Default policy: Secure Connections, 16-byte keys, MITM protection whenever
both sides have the IO for it, discoverable only while the settings page is
open or for a set time.

---

## 13. Effect on other parts of the OS

| Part | Change | Owner |
|---|---|---|
| `lib/unet/wireless/bluetooth.asm` | Retire the stub; `unet` takes IP packets from `ubt` BNEP | `unet` owner |
| `lib/usb` (new) | USB core and xHCI with isochronous transfers, see `lib/usb/ROADMAP.md` | To be decided |
| `lib/uaud` | Codecs and audio routing for A2DP, HFP and LE Audio | `uaud` owner |
| canvas | Settings → Bluetooth page, pairing prompts, input queue | canvas session |
| `apps/ush` | `bt` command | ush owner |
| `apps/uvm` | USB passthrough of a Bluetooth adapter, so guests can use it | uvm plan |

---

## 14. Open decisions for the user

| # | Question | Options |
|---|---|---|
| D1 | AAC for A2DP (AirPods sound best with it)? | Build AAC in `uaud` / SBC only |
| D2 | Proprietary codecs (aptX, LDAC)? | Leave out (proposed; licensing) / add later |
| D3 | Legacy PIN pairing for pre-2.1 devices? | Allow only after a warning (proposed) / never |
| D4 | Controller firmware files are third-party binaries that run on the radio chip, not on the CPU. Ship them? | Ship signed in `/app/lib/ubt/fw/` (proposed) / user installs them |
| D5 | Bluetooth SIG qualification and listing (needed to call a product "Bluetooth"; costs money) | Later, before any public release / never (internal use only) |
| D6 | Where USB lives | `lib/usb` (proposed; `lib/usb/ROADMAP.md` uses it) / under `lib/io` |
| D7 | Hardware to buy for 5.3 to 6.3 testing | Section 3 list / none for now (`sim/` only) |
| D8 | Quick-pairing pop-ups, which rely on vendor-specific advertising formats | Build later / leave out |
| D9 | Who owns combo-chip reset (RZ608 Wi-Fi + Bluetooth) | Wi-Fi driver owns the chip and `ubt` asks it (proposed) / shared |

# usb — Roadmap

**Part of:** Utkarsha OS, `lib/usb` — the USB host stack
**Status:** plan only; `lib/usb` does not exist as of 2026-11-06
**Scope:** every kind of USB device **except storage**. USB storage (pen
drives, disks, card readers) is deferred by decision on 2026-11-06, so that
devices work first.

`lib/usb` owns the USB host controllers, enumeration, hubs, power, and the
general device classes (keyboards, mice, serial, printers, smart cards and
others). Classes that belong to a bigger subsystem only get their transfers
from `lib/usb`; their protocol code lives with that subsystem:

| Device kind | Protocol code lives in |
|---|---|
| Bluetooth adapters | `lib/ubt` |
| Audio (speakers, microphones, headsets, MIDI) | `lib/uaud` |
| Webcams and capture | `lib/uvid` |
| Network adapters (Ethernet, Wi-Fi dongles, phone tethering) | `lib/unet/drivers` |
| Storage (deferred) | `lib/storage` |

Every part is built the same way as the rest of the OS:
- pure x86-64 assembly, statically linked;
- runs in ring 0 and is called directly, with no request layer in between;
- every descriptor and packet from a device is treated as hostile.

Legend: ✅ done · ◐ exists but unproven · ☐ planned

Line counts are estimates of assembly source, not including tests, and
could be off by ±50%.

---

## 1. What enterprise grade means here

| Area | Requirement |
|---|---|
| Safety | No descriptor, packet or timing from a device can crash, hang or corrupt the host. Every parser is length-checked and fuzzed |
| Isolation | Devices reach memory only through the IOMMU, and only their own buffers |
| Hot plug | Plugging and unplugging at any moment, including mid-transfer and in a storm of 100 events, never leaks or hangs |
| Reliability | A stuck device or a dead hub is reset or dropped alone; the rest of the bus keeps working |
| Latency | Keyboard and mouse: under 1 ms from the controller interrupt to the input queue |
| Throughput | Bulk transfers within 10% of the link's practical maximum (USB 2: ~40 MB/s, USB 3.x 5 Gbit/s: ~400 MB/s) |
| Isochronous | Audio, webcam and Bluetooth voice with no missed service intervals under full CPU load |
| Power | Idle devices suspend; link power management on USB 2 and 3; system sleep and resume keep devices working |
| Security | New devices can be held until authorised by policy; a new keyboard can be required to prove a human is there |
| Observability | Every controller, port, device, endpoint and error is visible in `/sys/dev/usb/`; full packet capture on demand |
| Multi-vendor | AMD, Intel and other xHCI controllers behave the same behind one interface; a quirk table covers known flaws |

---

## 2. Target hardware

Read from the development machine's device list on 2026-11-06.

| Item | Value | Effect on the plan |
|---|---|---|
| Host controllers | **2 × AMD xHCI** (PCI `1022:1639`), USB 3.1, interface version 1.10, each with a USB 3 root hub | First and main target |
| Bluetooth | MediaTek RZ608, `0E8D:0608`, composite | Needs bulk, interrupt and isochronous transfers (`lib/ubt`) |
| Webcam | HD Webcam, `5986:211C`, composite | Needs isochronous transfers (`lib/uvid`, UVC) |
| Wi-Fi dongle | Realtek 8811CU, `0BDA:C811` | Vendor driver in `lib/unet/drivers` |
| Card reader | Realtek, `0BDA:0129` | Storage: deferred |
| Built-in keyboard and touchpad | **Not USB**: keyboard on PS/2, touchpad on I²C-HID (checked 2026-11-06) | Drivers live in **`lib/input`** (decision U5) |

Testing before real hardware has two paths:
- **`sim/`, a software xHCI controller and device models** (keyboard,
  mouse, hub, Bluetooth, audio, webcam, network), run as host test suites.
  This is the main path, because QEMU runs are paused on the development
  machine.
- QEMU's emulated xHCI controller and devices, in software mode only, once
  QEMU runs are allowed again.

---

## 3. Key decisions

| # | Decision | Why |
|---|---|---|
| 1 | **xHCI first**; EHCI, OHCI and UHCI later | Every machine from the last ten years has xHCI; this machine has only xHCI |
| 2 | **No storage now** | User decision 2026-11-06: devices first. The existing `uxfs/drivers/usb_storage.asm` stub stays as it is until then |
| 3 | `lib/usb` owns transfers; subsystems own their protocols | Keeps Bluetooth, audio, video and networking with the code that understands them |
| 4 | Interrupt-driven with MSI-X; one interrupter per CPU group | Low latency and no polling; polling only as a fallback |
| 5 | All DMA through `lib/io/dma` with IOMMU mappings per device | A hostile device cannot read or write other memory |
| 6 | Direct `call` API with completion callbacks run on the caller's fiber | Same model as `lib/kvm` and `lib/ubt` |
| 7 | Driver matching from one table (class, subclass, protocol, vendor, product, interface) | One place to add devices and quirks |
| 8 | Every new device goes through the authorisation step | Enterprise policy and protection against fake keyboards |

---

## 4. Dependencies

| Need | Where | State |
|---|---|---|
| PCI enumeration, BARs, MSI-X | `lib/io/pci` | ◐ |
| DMA allocation, scatter-gather, IOMMU | `lib/io/dma` | ◐ |
| ACPI (xHCI ownership hand-off, Type-C via UCSI, port wake) | `lib/io/acpi` | ◐ basic tables only |
| Timers and fibers | `lib/time`, scheduler | ◐ |
| Input queue | canvas input stack (KRN-06) | ◐ |
| System sleep and resume | `kernel/power` | ◐ |
| Capability checks and audit log | `security/usrauth`, `/keep/log/sec` | ◐ |

---

## 5. Architecture

```
  canvas input   ubt   uaud   uvid   unet   uvm (passthrough)   storage (later)
       │          │      │      │      │          │
 ┌─────┴──────────┴──────┴──────┴──────┴──────────┴───────────────────────┐
 │ class/  hid hub cdc-acm serial printer ccid fido dfu tmc billboard ... │
 ├────────────────────────────────────────────────────────────────────────┤
 │ auth/  device authorisation, policy, audit                             │
 ├────────────────────────────────────────────────────────────────────────┤
 │ core/  enumeration · descriptors · driver match · transfers · errors   │
 │        hubs · power (suspend, LPM, wake) · quirks · capture            │
 ├────────────────────────────────────────────────────────────────────────┤
 │ hcd/   xhci │ ehci │ ohci │ uhci │ usb4 (host router)                  │
 ├────────────────────────────────────────────────────────────────────────┤
 │ typec/ UCSI, roles, power contracts, alternate modes                   │
 └────────────────────────────────────────────────────────────────────────┘
                lib/io/pci · lib/io/dma (IOMMU) · lib/io/acpi
```

### 5.1 Folder layout

```
lib/usb/
├── ROADMAP.md
├── README.md
├── usb.inc                public structures and constants
├── usb.asm                entry points, bus list
├── hcd/
│   ├── xhci/              init.asm ring.asm ctx.asm port.asm cmd.asm evt.asm
│   │                      xfer.asm isoc.asm stream.asm bw.asm pm.asm
│   │                      ecap.asm (hand-off, protocols) dbc.asm (debug)
│   ├── ehci/  ohci/  uhci/
│   └── usb4/              host router, tunnels (later)
├── core/                  enum.asm desc.asm match.asm urb.asm err.asm
│                          hub.asm power.asm lpm.asm quirks.asm capture.asm
├── class/
│   ├── hid/               USB HID transport only; reports go to the
│   │                      shared HID core in `lib/input/hid`
│   ├── cdc_acm/  serial/  printer/  ccid/  fido/  dfu/  tmc/  billboard/
├── typec/                 ucsi.asm role.asm pd.asm altmode.asm
├── auth/                  policy.asm authorise.asm audit.asm
├── dev/                   device mode (later)
├── sim/                   software xHCI and device models (tests only)
└── tests/
```

### 5.2 Where data lives

| Data | Path |
|---|---|
| USB policy (allowed classes, vendors, devices; new-device rules) | `/conf/usb/` |
| Live state: controllers, ports, devices, endpoints, counters | `/sys/dev/usb/` |
| Remembered authorised devices | `/data/usb/` |
| Audit log | `/keep/log/sec/usb` |
| Packet captures | `/keep/log/sys/usb/` (only when enabled) |

### 5.3 API shape

- `usb_driver_register(match_table, probe, remove)`
- `usb_submit(endpoint, transfer)` for control, bulk, interrupt and
  isochronous transfers; completion runs a callback on the caller's fiber
- `usb_set_config`, `usb_set_alt` (alternate settings, needed for
  Bluetooth voice, audio and webcams), `usb_clear_halt`, `usb_reset`
- `usb_suspend`, `usb_resume`, `usb_wake_enable`
- Events: device added, removed, authorised, suspended, error

---

## 6. Components

### 6.1 xHCI host controller

- ◐ Ownership hand-off from firmware (overruled after a second, SMIs
  off), reset, scratchpad buffers, device context array, 64-bit
  addressing (`hcd/xhci/init.asm`); host-tested against `sim/`
- ◐ Command ring and one event ring on interrupter 0, polled
  (`ring.asm`, `cmd.asm`)
- ☐ Several interrupters with MSI-X
- ☐ Transfer rings for control, bulk, interrupt and **isochronous**
  endpoints; bulk streams (needed later for fast storage)
- ◐ Port detection, reset, speed, warm reset for USB 3 links that did not
  train, change bits (`port.asm`); over-current still to do
- ◐ Slot and endpoint contexts, Address Device, Evaluate Context, Reset
  Endpoint with Set TR Dequeue after a stall (`cmd.asm`); Configure
  Endpoint and Stop Endpoint still to do
- ☐ Bandwidth checks and isochronous scheduling
- ☐ Error handling: stalls, babble, transaction errors, missed service,
  ring underrun and overrun, host controller error and full restart
- ☐ Link power management: USB 2 LPM, USB 3 U1/U2/U3
- ☐ Save and restore across system sleep
- ☐ **Debug Capability (DbC)**: a debug console over a USB cable, for
  laptops with no serial port

### 6.2 USB core

- ☐ Enumeration: address assignment, device, configuration, interface,
  endpoint, SuperSpeed companion, BOS, interface association and string
  descriptors (UTF-16 to UTF-8)
- ☐ Configuration choice for composite devices; alternate settings
- ☐ Driver matching from the table in decision 7
- ☐ Transfer API, timeouts, cancellation, retry rules
- ☐ Error recovery: clear halt, endpoint reset, port reset, re-enumeration
  when the device changes identity
- ☐ Hot plug and removal during transfers
- ☐ Power budget per port and hub
- ☐ Selective suspend, remote wakeup, wake from system sleep (keyboard,
  mouse)
- ☐ Quirk table by vendor, product and version
- ☐ Packet capture in a standard capture format that common analysers read

### 6.3 Hubs

- ☐ USB 2 hubs, including transaction translators for low- and full-speed
  devices behind high-speed hubs
- ☐ USB 3 hubs, route strings, hub depth up to 5
- ☐ Port power, over-current, indicators, hub suspend
- ☐ Hubs built into docks and monitors

### 6.4 Type-C and USB4

- ☐ UCSI through ACPI: port roles, cable orientation, power contracts
- ☐ Charging information in `/sys/dev/usb/`
- ☐ Alternate modes: DisplayPort (hand to `lib/hw/ugpu`)
- ☐ USB4 host router: USB 3, PCIe and DisplayPort tunnels; Thunderbolt-3
  compatible docks; device authorisation for PCIe tunnels (later phase)

### 6.5 Class drivers in `lib/usb`

| Class | Devices | Phase |
|---|---|---|
| HID transport: boot and report protocol, interrupt endpoints, SET_REPORT/GET_REPORT; parsing in `lib/input/hid` | Keyboards (with LEDs, all key rollover), mice, trackballs | 2 |
| HID: digitisers and touch | Touchpads (precision touchpad usages), touch screens, pens and tablets | 6 |
| HID: game devices | Gamepads, joysticks, wheels; rumble and LEDs | 6 |
| HID: other usages | Media and system keys, sensor hubs, battery and UPS devices | 6 |
| Hub | All hubs | 2 |
| CDC-ACM | Modems, development boards, serial consoles | 6 |
| USB-serial chips | FTDI, Silicon Labs CP210x, WCH CH34x, Prolific PL2303 | 6 |
| Printer class, IPP over USB | Printers and scanners that support it | 6 |
| CCID | Smart cards and readers (hand to `lib/crypto`) | 6 |
| FIDO / CTAP over HID | Security keys (hand to `security/`) | 6 |
| DFU | Firmware update of USB devices | 6 |
| USBTMC | Lab instruments | 6 |
| Billboard | Reports unsupported Type-C alternate modes | 7 |

### 6.6 Classes handled by other libraries

| Class | Library | Needs from `lib/usb` | Phase |
|---|---|---|---|
| Bluetooth (class E0) | `lib/ubt` | Bulk, interrupt, isochronous with alternate settings | 5 |
| Audio (UAC 1, 2 and 3; MIDI) | `lib/uaud` | Isochronous with feedback endpoints | 5 |
| Video (UVC) | `lib/uvid` | Isochronous and bulk, high bandwidth | 5 |
| Network: CDC-ECM, CDC-NCM, phone tethering, vendor Ethernet (Realtek, ASIX) | `lib/unet/drivers` | Bulk, interrupt | 5 |
| Wi-Fi dongles (Realtek 8811CU first) | `lib/unet/drivers` | Bulk, firmware download | 5 |

### 6.7 Deferred: storage

Not built now (decision 2026-11-06):
- Mass storage Bulk-Only Transport and USB Attached SCSI (UAS)
- Card readers (the Realtek `0BDA:0129` on this machine)
- Moving `lib/storage/uxfs/drivers/usb_storage.asm` onto `lib/usb`

Phone and camera file transfer (MTP/PTP) is deferred with storage
(decision U1).

### 6.8 Security and management

- ☐ Device authorisation: new devices stay unconfigured until policy
  allows them; known devices remembered by vendor, product, serial and port
- ☐ Policy in `/conf/usb/`: allowed and blocked classes, vendors and
  devices; rules for a locked screen (no new devices while locked)
- ☐ New-keyboard check, **on by default** (decision U3): a keyboard plugged
  in after boot types a shown code before its input counts; an admin can
  turn it off in `/conf/usb/`
- ☐ Interfaces of one device authorised separately, so a "storage stick"
  cannot quietly add a keyboard interface
- ☐ IOMMU mapping per device; USB4 PCIe tunnels only after authorisation
- ☐ Audit log of every device added, refused or removed
- ☐ Capability checks: which apps may open raw USB devices
- ☐ Hand-off to `security/malwarescan/usb_scan` when storage arrives
- ☐ Passthrough of a whole device to `apps/uvm` guests

### 6.9 Tools

- ☐ `usb` command: list the device tree, show descriptors, show power and
  errors, authorise and block, start and stop capture
- ☐ Descriptor decoder that prints readable text

---

## 7. Phases

### Phase 0 — Foundations

- ☑ `usb.inc`: device, interface, endpoint, association, BOS and transfer
  structures
- ☑ Descriptor parsers (`core/desc.asm`) with fuzzing from day one: 20 000
  rounds per run against a reference parser
- ◐ `sim/`: a software xHCI controller and device models (keyboard, mouse,
  Bluetooth radio, SuperSpeed disk); grows with each phase

Estimate: ~2 000 lines.

### Phase 1 — xHCI bring-up (`sim/`)

- ◐ Controller init, rings, port detection, devices at full, high and
  SuperSpeed enumerated over control transfers (`core/enum.asm`); 48
  host checks. Interrupters with MSI-X, PCI attach and the `usb` command
  still to do

Demo: `usb` lists the simulated keyboard with its descriptors.
Estimate: ~6 000 lines.

### Phase 2 — Core, hubs, keyboard and mouse

- ☐ Full enumeration, driver matching, interrupt and bulk transfers, hot
  plug
- ☐ Hubs (USB 2 and 3)
- ☐ HID keyboard and mouse to the canvas input queue

Demo: simulated keyboard and mouse events reach the input queue; real
devices follow in Phase 3.
Estimate: ~9 000 lines.

### Phase 3 — Real hardware

- ☐ The two AMD xHCI controllers: firmware hand-off, quirks, every port
- ☐ Debug Capability console
- ☐ External USB keyboard and mouse on the laptop

Estimate: ~3 000 lines.

### Phase 4 — Isochronous and power

- ☐ Isochronous transfers and bandwidth scheduling
- ☐ Selective suspend, remote wakeup, LPM, system sleep and resume

Estimate: ~5 000 lines.

### Phase 5 — Devices for other libraries

- ☐ Bluetooth (RZ608) for `lib/ubt`
- ☐ Webcam for `lib/uvid`, USB audio for `lib/uaud`
- ☐ CDC network and the Realtek Wi-Fi dongle for `lib/unet`

Estimate: ~2 000 lines in `lib/usb`; the class code is counted in each
library.

### Phase 6 — General classes

- ☐ Every class in the table in 6.5 marked Phase 6

Estimate: ~14 000 lines.

### Phase 7 — Type-C and USB4 (in parallel with Phases 3 to 6)

Decision U4: built at the same time as the other phases, not after them.
It starts once Phase 2 (core and hubs) works.

- ☐ UCSI, roles, power contracts, DisplayPort alternate mode, Billboard
- ☐ USB4 host router: discovery, link training, router configuration
- ☐ Tunnels: USB 3, PCIe, DisplayPort; bandwidth allocation between them
- ☐ USB4 version 2 (80 Gbit/s and asymmetric links)
- ☐ Thunderbolt 3 compatible devices and docks; dock chains
- ☐ Authorisation of PCIe tunnels before any device behind them gets DMA

Estimate: ~17 000 lines.

### Phase 8 — Older controllers and device mode

Decision U2: every older controller type is supported.

- ☐ EHCI (USB 2 high speed): async and periodic schedules, split
  transactions, isochronous
- ☐ OHCI and UHCI (USB 1.1), alone and as EHCI companions; port routing
  between EHCI and its companions
- ☐ EHCI debug port, for older machines with no serial port
- ☐ Firmware hand-off and legacy keyboard emulation shutdown for each
- ☐ Device mode, for machines with a USB device controller (later)

Estimate: ~12 000 lines.

### Phase 9 — Security and management

- ☐ Everything in 6.8

Estimate: ~4 000 lines.

### Phase 10 — Hardening

- ☐ Fuzzing of every descriptor and class parser
- ☐ Hot-plug storms, unplug during transfers, broken and lying devices
- ☐ 72-hour soak with keyboard, mouse, Bluetooth, webcam, audio and network
  at once
- ☐ Interop list of tested devices and docks

### Later — Storage

- ☐ Everything in 6.7, when the user decides

---

## 8. Rough size

| Part | Lines (±50%) |
|---|---|
| xHCI | 11 000 |
| Core, hubs, power, quirks, capture | 14 000 |
| HID transport (parser in `lib/input`) | 1 000 |
| Other classes in `lib/usb` | 9 000 |
| Type-C and USB4 | 17 000 |
| EHCI, OHCI, UHCI, device mode | 12 000 |
| Security, management, tools | 5 000 |
| `sim/` software xHCI and device models | 8 000 |
| **Total** | **~77 000** |

Not counted: class code in `lib/ubt`, `lib/uaud`, `lib/uvid` and
`lib/unet` (a USB Wi-Fi driver alone is large), and storage.

Phases 1 to 5 (everything needed for keyboards, mice, Bluetooth, webcam,
audio and network on this machine) are about 27 000 lines.

---

## 9. Open decisions for the user

| # | Question | Options |
|---|---|---|
| U1 | Phone and camera file transfer (MTP/PTP) | **Decided 2026-11-06:** later, with storage |
| U2 | Older machines without xHCI (EHCI, OHCI, UHCI) | **Decided 2026-11-06:** support all (Phase 8) |
| U3 | New-keyboard check after boot | **Decided 2026-11-06:** on by default |
| U4 | USB4 and Thunderbolt docks | **Decided 2026-11-06:** all of it, built in parallel with the other phases (Phase 7) |
| U5 | Built-in keyboard and touchpad (PS/2, I²C) | **Decided 2026-11-06:** new `lib/input` |
| U6 | Where the shared HID core lives | **Decided 2026-11-06:** `lib/input/hid`; plan in `lib/input/ROADMAP.md` |

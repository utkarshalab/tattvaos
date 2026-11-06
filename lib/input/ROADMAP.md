# input — Roadmap

**Part of:** Utkarsha OS, `lib/input` — input devices and the shared HID core
**Status:** Phases 0 and 1 written and host-tested (2026-11-06); not yet run on
QEMU or real hardware
**Decided 2026-11-06:** built-in keyboards and touchpads (PS/2, I²C) are
driven here, not in `lib/usb` and not in canvas.

`lib/input` turns hardware into input events and hands them to canvas
through `ut_input_register_callback`. It owns:

- the **event core**: device list, event delivery, device information,
  exclusive grabs;
- the **HID core**: the report descriptor parser and usage handling shared
  by every HID transport (USB, Bluetooth, I²C, SPI);
- the **non-USB drivers**: PS/2 (i8042), I²C-HID, SPI-HID, platform keys and
  switches, sensors, virtual devices.

USB and Bluetooth only move bytes: `lib/usb` and `lib/ubt` pass HID reports
to the HID core here, so there is one parser in the whole OS.

### Boundary with canvas

Decision 0009 in canvas already splits the work. This plan keeps that split.

| `lib/input` (here) | canvas |
|---|---|
| Drivers, HID parsing, scan codes to key codes | Keymaps, layouts, compose, key repeat |
| Raw relative and absolute motion, buttons, scroll | Pointer acceleration, scroll speed, button remapping |
| Multi-touch contact frames with sizes and pressure | Gestures, palm rejection, disable-while-typing |
| Pen position, pressure, tilt, buttons | Pressure curves, inking |
| Device information, LEDs, haptics output | Focus, routing to windows, shortcuts |
| Hardware quirks (wrong ranges, swapped axes, broken firmware) | Behaviour quirks and user settings |

Every part is built the same way as the rest of the OS:
- pure x86-64 assembly, statically linked;
- runs in ring 0 and is called directly, with no request layer in between;
- every report from a device is treated as hostile.

Legend: ✅ done · ◐ exists but unproven · ☐ planned

Line counts are estimates of assembly source, not including tests, and
could be off by ±50%.

---

## 1. What enterprise grade means here

| Area | Requirement |
|---|---|
| Latency | Under 1 ms from the device interrupt to canvas; no extra delay under full CPU load |
| Reliability | A stuck or chattering device is reset or ignored alone; input never stops because of one device |
| Safety | No report or descriptor can crash or hang the host; every parser is length-checked and fuzzed |
| Security | Only canvas (and authorised grab holders) receive events; a new keyboard proves a human is there (USB decision U3); the secure attention sequence cannot be faked by a virtual device |
| Coverage | Every built-in keyboard and touchpad on current laptops works; any HID device works at least as a generic device |
| Power | Wake from keyboard, touchpad, lid and power button; touchpad off when the lid closes |
| Observability | Every device, its capabilities, its event rate and its errors visible in `/sys/dev/input/`; live event view on demand |
| Stability | Device IDs stay the same across reboots (from ACPI, PCI and USB paths) |

---

## 2. Target hardware

Read from the development machine's device list on 2026-11-06 (an MSI
laptop with a Ryzen 7 5700U).

| Device | Bus and ID | Driver here |
|---|---|---|
| Built-in keyboard | **PS/2**, ACPI `MSI0007` | `ps2/` keyboard |
| Touchpad | **I²C-HID**, ACPI `PNP0C50`: touchpad, mouse and vendor collections | `i2c_hid/` + HID core |
| Touchpad fallback | PS/2 mouse, ACPI `MSNB0001` (the same touchpad in its basic mode) | `ps2/` mouse, used only if I²C fails |
| I²C controller | AMD, ACPI `AMDI0010` | `lib/io/i2c` (Section 4) |
| GPIO controller | AMD, ACPI `AMDI0030` (the touchpad's interrupt line) | `lib/io/gpio` (Section 4) |
| Lid switch | ACPI `PNP0C0D` | `plat/` |
| Power button | ACPI `PNP0C0C` | `plat/` |
| Laptop hotkeys (brightness, airplane mode, fan) | Vendor ACPI methods, to be checked on bare metal | `plat/vendor/msi` |

So this machine needs **three** new drivers before its own keyboard and
touchpad work: PS/2 for the keyboard, and I²C plus GPIO for the touchpad.

---

## 3. Key decisions

| # | Decision | Why |
|---|---|---|
| 1 | **One HID core in `lib/input/hid`** (USB decision U6, proposed) | USB, Bluetooth, I²C and SPI devices all speak HID; one parser means one set of bugs and one fuzz target |
| 2 | **PS/2 keyboard first** | Fastest path to typing on this machine and on almost every PC |
| 3 | I²C-HID touchpad before PS/2 touchpad protocols | Current laptops expose precision touchpads over I²C; the PS/2 vendor protocols are only a fallback |
| 4 | Events delivered with the canvas record from `KERNEL_NEEDS.md` step 3 | Canvas already consumes it. New record types (touch frame, pen, switch, LED) are added by agreement with canvas, with a version number |
| 5 | The callback runs on a driver fiber, not inside an interrupt handler | Matches `KERNEL_NEEDS.md` ("one call at a time from any fiber"); the interrupt only queues the report |
| 6 | Hardware quirks live here, behaviour quirks in canvas | Canvas TCH-14 keeps user-facing quirks; wrong ranges and broken firmware are fixed before events leave `lib/input` |
| 7 | Virtual devices only with a capability | Remote desktop, accessibility tools and tests may inject events, but never the secure attention sequence |

---

## 4. Dependencies

| Need | Where | State | Needed by |
|---|---|---|---|
| ACPI namespace: device IDs, `_CRS` resources, `_DSM` (I²C-HID descriptor address), `_PRW` (wake), notify events | `lib/io/acpi` **AML interpreter** (decision I1) | ◐ static tables only (FADT, MADT, MCFG); interpreter **not found** | Phase 1 (lid and power button), Phase 3 |
| I²C host controller driver (AMD and Intel DesignWare) | `lib/io/i2c` (decision I2) | **Not found** | Phase 3 |
| GPIO controller driver with interrupts (AMD first, then Intel) | `lib/io/gpio` (decision I2; also used by `lib/ubt`) | **Not found** | Phase 3 |
| SPI host controller | `lib/io/spi` (decision I2) | **Not found** | Phase 7 |
| Interrupt routing (IO-APIC, legacy IRQ 1 and 12 for PS/2) | `lib/io/intr` | ◐ | Phase 1 |
| USB HID transport | `lib/usb/class/hid` | Planned (USB Phase 2) | Phase 2 |
| Bluetooth HID and HOGP transport | `lib/ubt` | Planned (ubt Phase 4) | Phase 5 |
| Canvas input source | canvas `input/` | ◐ routing done, source missing | Phase 0 |
| Capability checks, audit log | `security/usrauth`, `/keep/log/sec` | ◐ | Phase 8 |

The **AML interpreter** is the largest hidden dependency. Most platform
devices (touchpads, lid, buttons, hotkeys) are described in ACPI bytecode,
not in static tables. Decision I1 puts it in `lib/io/acpi`, finished before
input Phase 3. Phase 1 uses the fixed legacy resources (i8042 at ports
0x60 and 0x64, IRQ 1) so typing does not wait for it. The power button
(`PNP0C0C`) and lid (`PNP0C0D`) on this machine are control-method devices:
they report through AML, so they wait for ACPI Phase 3 too.

#### AML interpreter scope (full plan: `lib/io/acpi/ROADMAP.md`)

- Table loading: DSDT and every SSDT, with checksums
- Bytecode parser and interpreter: all named objects, control flow, method
  calls with arguments and locals, buffers, packages, strings, field units,
  operation regions (system memory, I/O ports, PCI config, embedded
  controller, GPIO, generic serial bus for I²C)
- Namespace walk: `_HID`, `_CID`, `_UID`, `_ADR`, `_STA`, `_INI`, `_CRS`
  (resource templates: memory, I/O, IRQ, GPIO, I²C and SPI connections),
  `_DSM`, `_PRW`, `_PS0`/`_PS3`, `_OSC`, `_PRT` (PCI interrupt routing)
- Notify events and the embedded controller (lid, buttons, hotkeys,
  battery, thermal)
- Hostile-input rules: firmware bytecode is checked like any untrusted
  input, with loop and recursion limits and a time budget per method
- Rough size: about 38 000 lines for all of ACPI, of which about 21 500
  are needed before input Phase 3

---

## 5. Architecture

```
                         canvas  (ut_input_register_callback)
                            │
 ┌──────────────────────────┴──────────────────────────────────────────┐
 │ core/  device list · event ring · device info · grabs · injection   │
 │        new-device check · LEDs and haptics out · power and wake     │
 ├─────────────────────────────────────────────────────────────────────┤
 │ hid/   report descriptor parser · usage tables · report → events    │
 │        output and feature reports · hardware quirks                 │
 ├──────────┬────────────┬──────────┬──────────┬───────────┬───────────┤
 │ ps2/     │ i2c_hid/   │ spi_hid/ │ plat/    │ sensor/   │ virt/     │
 │ i8042    │            │          │ lid, pwr │ AMD SFH,  │ virtio-   │
 │ kbd,     │            │          │ hotkeys, │ Intel ISH │ input,    │
 │ mouse,   │            │          │ switches │           │ injection │
 │ touchpad │            │          │          │           │           │
 └──────────┴─────┬──────┴────┬─────┴────┬─────┴───────────┴───────────┘
      ▲           │           │          │
 lib/usb ─► hid/  lib/io/i2c  lib/io/spi lib/io/acpi, lib/io/gpio
 lib/ubt ─► hid/
```

### 5.1 Folder layout

```
lib/input/
├── ROADMAP.md
├── README.md
├── input.inc              event records, device info, capability bits
├── input.asm              entry points, ut_input_* exports
├── core/                  dev.asm ring.asm info.asm grab.asm inject.asm
│                          newdev.asm led.asm haptic.asm pm.asm stats.asm
├── hid/                   parse.asm (report descriptors) usage/ (tables)
│                          kbd.asm mouse.asm digitizer.asm (touch, pen)
│                          consumer.asm system.asm game.asm sensor.asm
│                          battery.asm haptic.asm quirks.asm
├── ps2/                   i8042.asm kbd.asm mouse.asm
│                          tp/ (synaptics alps elantech focaltech trackpoint)
├── i2c_hid/               i2c_hid.asm
├── spi_hid/               spi_hid.asm
├── plat/                  lid.asm power.asm sleep.asm tablet_mode.asm
│                          vendor/ (msi, then other laptop makers)
├── sensor/                amd_sfh.asm intel_ish.asm (rotation, lid angle,
│                          ambient light)
├── game/                  vendor gamepad protocols (Xbox, PlayStation,
│                          Nintendo controllers)
├── virt/                  virtio_input.asm uinput.asm (virtual devices)
├── sim/                   simulated i8042, I²C-HID and recorded devices
└── tests/                 HID descriptor corpus, recorded event traces
```

### 5.2 Event records

Canvas's 24-byte record (`KERNEL_NEEDS.md` step 3) stays the base:

| `type` | Meaning | Status |
|---|---|---|
| 1 | Key | In canvas today |
| 2 | Relative motion | In canvas today |
| 3 | Absolute position | In canvas today |
| 4 | Button | In canvas today |
| 5 | Scroll (with high-resolution steps added in the `value` scale) | In canvas today |
| 6 | Touch contact | Proposed below |
| 7 | Pen position and state | Proposed below |
| 8 | Pen axes | Proposed below |
| 9 | Switch | Proposed below |
| 10 | Device added, removed, changed | Proposed below |

Key codes are one table shared by every transport: PS/2 scan code sets 1
and 2, HID keyboard usages and consumer usages all map to the same codes.

#### Proposed layouts for the new types (decision I3)

All keep the same 24 bytes: `type` (4), `code` (4), `value` (4), `device`
(4), `time` (8). Coordinates are in device units; `ut_input_device_info`
gives `max_x`, `max_y` and the resolution, so canvas can scale them.

| `type` | `code` bits | `value` bits |
|---|---|---|
| 6 touch | 0–7 slot (0–254); 8–11 phase: 0 down, 1 move, 2 up, 3 **frame end** (all contacts of one scan sent), 4 cancel (palm or lost contact); 12 confidence (the device thinks it is a finger); 16–23 pressure (0–255); 24–31 contact size (0–255) | 0–15 x, 16–31 y |
| 7 pen position | 0 in range, 1 tip down, 2 eraser, 3 barrel button 1, 4 barrel button 2, 5 inverted; 16–23 tool kind: 0 pen, 1 eraser end, 2 brush, 3 airbrush | 0–15 x, 16–31 y |
| 8 pen axes | 0–15 pressure (0–65535) | 0–7 tilt x (signed degrees), 8–15 tilt y (signed degrees), 16–24 rotation (0–359 degrees) |
| 9 switch | Switch: 0 lid, 1 tablet mode, 2 dock, 3 headphone jack, 4 camera shutter, 5 microphone mute, 6 keypad slide | 1 on or closed, 0 off or open |
| 10 device | 0 added, 1 removed, 2 changed (capabilities, mode or battery) | Capability bits from `InputDevInfo.caps` |

Rules:
- A touch scan is a run of type 6 records ended by one with phase 3; canvas
  applies them together. Up and cancel free the slot.
- A pen sample is one type 7 record followed by one type 8 record with the
  same time.
- Canvas ignores any `type` it does not know, so new types can be added
  without breaking it.
- Canvas owns `input/`, so the canvas session has to accept these layouts
  before `lib/input` Phase 3 sends them. Until then, touchpads send types
  2, 4 and 5 (mouse-like) only.

### 5.3 Where data lives

| Data | Path |
|---|---|
| Hardware quirks shipped with the OS | `/app/lib/input/quirks` |
| Admin settings (new-device check, allowed virtual devices) | `/conf/input/` |
| Live state: devices, capabilities, rates, errors | `/sys/dev/input/` |
| Audit log (new devices, grabs, injection) | `/keep/log/sec/input` |

User settings (layouts, acceleration, gestures) stay with canvas.

---

## 6. Components

### 6.1 Event core

- ☐ `ut_input_register_callback`, `ut_input_unregister_callback`,
  `ut_input_device_info`, `ut_input_grab` (canvas contract §3.8)
- ☐ Device list with stable IDs from ACPI, PCI, USB and Bluetooth paths
- ☐ Per-device ring, timestamps from the interrupt, batching per frame
- ☐ LEDs (Caps Lock, Num Lock, Scroll Lock, mute, microphone mute) sent back
  to every keyboard
- ☐ Haptics and force feedback output
- ☐ Hot plug: devices from USB and Bluetooth come and go at any time
- ☐ New-device check for keyboards from every transport (USB decision U3,
  on by default); built-in PS/2 and I²C devices are trusted at boot
- ☐ Wake sources: keyboard, touchpad, lid, power button
- ☐ Battery level of wireless input devices, reported to `/sys`

### 6.2 HID core

- ☐ Report descriptor parser: main, global and local items, nested
  collections, report IDs, long items, push and pop, every bound checked
- ☐ Usage pages: generic desktop, keyboard, LEDs, buttons, consumer,
  digitizers (touchpad, touch screen, pen), game controls, simulation,
  sensors, battery system, power device, haptics, vendor-defined (passed
  through)
- ☐ Reports to events; output and feature reports (LEDs, touchpad mode
  switch, haptics)
- ☐ Precision touchpad: mode switch from mouse mode to multi-touch mode,
  contact count, confidence bit, button type, latency mode
- ☐ Multi-collection devices (this touchpad has touchpad, mouse and vendor
  collections)
- ☐ Hardware quirks: wrong logical ranges, swapped or inverted axes, broken
  descriptors replaced by fixed ones
- ☐ Interfaces for transports: `hid_attach(transport_ops, descriptor)`,
  `hid_input_report(dev, bytes, len)`, `hid_send_report`

### 6.3 PS/2 (i8042)

- ☐ Controller detection (ACPI, then legacy probe), self-test, port tests,
  translation mode, firmware hand-off from USB legacy emulation
- ☐ Keyboard: scan code sets 1 and 2, extended and Pause/Print Screen
  sequences, LEDs, typematic off (canvas repeats keys), reset and re-detect
- ☐ Mouse: standard, wheel (IntelliMouse 3 and 4 byte), five buttons,
  resync on lost bytes
- ☐ Touchpad and pointing stick protocols over PS/2, for machines without
  I²C-HID: Synaptics, ALPS, Elantech, FocalTech, TrackPoint
- ☐ Suspend and resume

### 6.4 I²C-HID and SPI-HID

- ☐ I²C-HID: HID descriptor from the ACPI `_DSM` address, report
  descriptor, reset, power on and sleep, input report reading on GPIO
  interrupt, output and feature reports through command and data registers
- ☐ Interrupt storms and devices stuck asserting the line: detect and reset
- ☐ SPI-HID (newer laptops): same flow over SPI

### 6.5 Platform keys and switches

- ☐ Power button, sleep button (ACPI fixed and control-method buttons)
- ☐ Lid switch, with the "touchpad off when lid closed" rule
- ☐ Tablet-mode and dock switches
- ☐ Laptop hotkeys through vendor ACPI methods: MSI first, then other
  laptop makers as they are tested
- ☐ Privacy switches (camera shutter, microphone) reported as switches

### 6.6 Sensors

- ☐ AMD Sensor Fusion Hub and Intel Integrated Sensor Hub: accelerometer
  (screen rotation), lid angle, ambient light, presence
- ☐ HID sensor usages from any transport

### 6.7 Touch screens, pens and game devices

- ☐ Touch screens over I²C-HID and USB
- ☐ Pens: HID pen usages, USI pens, Wacom-style pens over I²C-HID
- ☐ Gamepads: generic HID; vendor protocols for Xbox (including its
  non-HID USB protocol), PlayStation and Nintendo controllers; rumble,
  LEDs, motion sensors, touchpads on controllers
- ☐ Joysticks, wheels, pedals (HID simulation usages)

### 6.8 Virtual devices

- ☐ virtio-input, for when Utkarsha OS runs as a guest (including in
  `apps/uvm`)
- ☐ Injection API with a capability: remote desktop, accessibility tools,
  automated tests; injected events are marked and never count as the
  secure attention sequence

### 6.9 Tools

- ☐ `input` command: list devices and capabilities, live event view,
  decode a HID descriptor, measure latency and event rate, show quirks
  applied

---

## 7. Phases

### Phase 0 — Event core and canvas link

- ◐ `input.inc`, device list, event ring, the four `ut_input_*` functions,
  exported to UBF programs (`kernel/exec/exports.asm`); input fiber
  (`kernel.asm`)
- ◐ Simulated i8042 and keyboard for host tests (`tests/sim_ps2.py`);
  simulated HID devices come with Phase 2
- ☐ Canvas receives events through the real callback (needs a boot)

Estimate: ~3 000 lines.

### Phase 1 — PS/2 keyboard

- ◐ i8042 controller: detection, self-test, translation, IRQ 1
  (`ps2/i8042.asm`)
- ◐ Keyboard: reset, set 2, scan code set 1 decoding including 0xE0 keys,
  Print Screen and Pause, repeat suppression, lock-key LEDs with ACK,
  resend and timeout handling (`ps2/kbd.asm`)
- ☐ Run on QEMU and on this machine
- Moved: power button and lid need AML on this machine, so they are in
  ACPI Phase 3

Demo: type on the built-in keyboard at the canvas login screen.
Estimate: ~3 000 lines.

### Phase 2 — HID core and USB HID

- ☐ Full report descriptor parser and the keyboard, mouse and consumer
  usages
- ☐ USB keyboards and mice through `lib/usb` (USB Phase 2)

Estimate: ~5 000 lines.

### Phase 3 — Built-in touchpad

Prerequisite: the AML interpreter (I1); `lib/io/i2c` and `lib/io/gpio` (I2,
built in this phase if no one else has); canvas accepting the record types
in 5.2 (I3).

- ☐ AMD I²C controller, AMD GPIO controller with interrupts
- ☐ I²C-HID transport
- ☐ Precision touchpad: multi-touch mode switch, contact frames (record
  type 6 agreed with canvas)

Demo: pointer, tap and two-finger scroll on the built-in touchpad (gestures
by canvas).
Estimate: ~6 000 lines (including I²C and GPIO).

### Phase 4 — PS/2 mice and touchpad protocols

- ☐ PS/2 mouse protocols, then Synaptics, ALPS, Elantech, FocalTech and
  TrackPoint, for machines without I²C-HID

Estimate: ~7 000 lines.

### Phase 5 — Bluetooth input

- ☐ Classic HID and HOGP reports from `lib/ubt` (ubt Phase 4)

Estimate: ~500 lines here.

### Phase 6 — Platform keys and sensors

- ☐ Laptop hotkeys (MSI first), tablet mode and privacy switches
- ☐ Sensor hubs: AMD first, then Intel

Estimate: ~7 000 lines.

### Phase 7 — Touch screens, pens, game devices, SPI, virtual devices

- ☐ Everything in 6.4 (SPI-HID), 6.7 and 6.8

Estimate: ~9 000 lines.

### Phase 8 — Security and management

- ☐ New-device check across all transports, grabs, injection capability,
  audit log, admin settings

Estimate: ~2 500 lines.

### Phase 9 — Hardening

- ☐ Fuzzing of the HID parser with a corpus of real descriptors
- ☐ Replay of recorded event traces from real devices in host tests
- ☐ Chattering keys, interrupt storms, devices that vanish mid-report
- ☐ Latency measurement on real hardware

---

## 8. Rough size

| Part | Lines (±50%) |
|---|---|
| Event core, security, tools | 6 500 |
| HID core (all usage pages, quirks) | 8 000 |
| PS/2 (keyboard, mouse, touchpad protocols) | 9 000 |
| I²C-HID, SPI-HID | 2 500 |
| Platform keys and switches | 3 000 |
| Sensor hubs | 4 000 |
| Gamepad vendor protocols, pens, touch screens | 5 000 |
| Virtual devices | 1 000 |
| `sim/` | 4 000 |
| **Total** | **~43 000** |

Not counted: the host drivers in `lib/io/i2c` (~7 500), `lib/io/gpio`
(~7 000) and `lib/io/spi` (~3 500), each planned in its own ROADMAP.md.

The HID core moves here from `lib/usb`, so the USB plan shrinks by about
7 000 lines.

Phases 0 to 3 (built-in keyboard, USB keyboard and mouse, built-in touchpad
on this machine) are about 17 000 lines, roughly 3 to 5 sessions.

---

## 9. Open decisions for the user

| # | Question | Options |
|---|---|---|
| I1 | AML interpreter | **Decided 2026-11-06:** in `lib/io/acpi`, finished before input Phase 3; Phase 1 uses hard-coded resources |
| I2 | I²C, SPI and GPIO host drivers | **Decided 2026-11-06:** `lib/io/i2c`, `lib/io/spi`, `lib/io/gpio` |
| I3 | New event record types | **Decided 2026-11-06:** layouts proposed in 5.2; the canvas session must accept them before Phase 3 |

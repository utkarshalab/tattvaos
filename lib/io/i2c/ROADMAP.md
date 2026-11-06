# i2c — Roadmap

**Part of:** Utkarsha OS, `lib/io/i2c` — I²C, SMBus and I3C host controllers
**Status:** plan only; `lib/io/i2c` does not exist as of 2026-11-06
**Decided 2026-11-06:** I²C lives here (input decision I2)

I²C is the slow two-wire bus that connects touchpads, touchscreens,
sensors, smart audio amplifiers, USB-C controllers, battery gauges and
EEPROMs. SMBus is its stricter form on PC chipsets (memory module data,
sensors). I3C is its faster successor. `lib/io/i2c` drives the host
controllers and gives device drivers one transfer interface.

The display's own I²C channel (DDC, for monitor information) belongs to
canvas, by canvas decision 0009, and is not part of this library.

Built like the rest of the OS: pure x86-64 assembly, statically linked,
ring 0, direct calls.

Legend: ✅ done · ◐ exists but unproven · ☐ planned. Line counts ±50%.

---

## 1. Requirements

| Area | Requirement |
|---|---|
| Correctness | Standard (100 kHz), fast (400 kHz), fast-mode plus (1 MHz) and high speed (3.4 MHz) with correct timings from ACPI; 7- and 10-bit addresses; repeated start; clock stretching |
| Reliability | A device holding the bus low is recovered (nine clock pulses, then controller reset); a lost arbitration is retried; one bad device never blocks the bus for others |
| Latency | A touchpad report (about 30 bytes at 400 kHz or 1 MHz) read within 1 ms of its interrupt |
| Safety | Raw bus access only with a capability; battery, charger and EC addresses protected from writes by default |
| Observability | Every bus, device, transfer count, error, NACK and recovery in `/sys/dev/i2c/` |

---

## 2. Target hardware

| Controller | Where | Phase |
|---|---|---|
| **AMD I²C** (`AMDI0010`) on this machine: DesignWare-based | AMD Ryzen laptops | 1 |
| Intel LPSS I²C (DesignWare-based, PCI, with DMA) | Intel laptops | 2 |
| AMD FCH SMBus and Intel chipset SMBus | Most PCs | 3 |
| I3C host controllers (MIPI I3C HCI) | Newest laptops and servers | 4 |

---

## 3. Components

- ☐ DesignWare core: init, speed and timing setup (from ACPI timing methods
  or `_DSD` values), FIFO handling, interrupts, DMA on Intel LPSS
- ☐ Transfer interface: `i2c_xfer(bus, msgs, count)` with read, write and
  combined messages; `i2c_smbus_*` helpers (byte, word, block, process
  call, packet error checking)
- ☐ Bus recovery through `lib/io/gpio` when the clock pin is reachable;
  controller reset otherwise
- ☐ Device discovery from ACPI `I2cSerialBus` resources; no blind probing
  except on SMBus, and only at safe addresses
- ☐ Generic serial bus operation region handler, so AML can talk to I²C
  devices (battery gauges, USB-C controllers)
- ☐ SMBus controllers: AMD FCH and Intel chipset; host notify; SMBus alert;
  memory module SPD reading (memory size, speed, serial in `/sys`)
- ☐ I3C: dynamic addressing, in-band interrupts, legacy I²C devices on an
  I3C bus
- ☐ Shared-bus locking with firmware (some platforms share a bus with the
  embedded controller or system management firmware)
- ☐ Protection list: writes refused to battery, charger and EC addresses
  unless allowed by policy
- ☐ Tools: `i2c` command to list buses and devices, read registers (admin),
  show errors

---

## 4. Phases

| Phase | Work | Lines |
|---|---|---|
| 1 | AMD DesignWare controller, transfer interface, ACPI discovery (for the touchpad) | ~2 000 |
| 2 | Intel LPSS with DMA; bus recovery; generic serial bus region for AML | ~1 500 |
| 3 | SMBus controllers, SPD, protection list, tools | ~1 500 |
| 4 | I3C | ~2 500 |
| 5 | Hardening: stuck-bus and NACK fault injection, soak under touchpad load | — |
| **Total** | | **~7 500** |

Phase 1 is part of input Phase 3 (the built-in touchpad).

---

## 5. Consumers

| Consumer | Devices |
|---|---|
| `lib/input` | I²C-HID touchpads, touchscreens, pens, sensors |
| `lib/uaud` | Smart amplifiers, audio codecs on I²C |
| `lib/usb/typec` | USB-C port controllers |
| `lib/io/acpi` | Battery gauges and other devices reached from AML |
| `lib/hw` | Temperature and voltage sensors, memory module data |

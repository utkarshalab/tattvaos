# spi — Roadmap

**Part of:** Utkarsha OS, `lib/io/spi` — SPI host controllers
**Status:** plan only; `lib/io/spi` does not exist as of 2026-11-06
**Decided 2026-11-06:** SPI lives here (input decision I2)

SPI is a fast four-wire bus. On PCs it connects SPI-HID keyboards and
touchpads on some laptops, fingerprint readers, some TPMs and the system
firmware flash chip. `lib/io/spi` drives the host controllers and gives
device drivers one transfer interface.

This machine has no SPI device that needs a driver today, so SPI comes
after I²C and GPIO.

Built like the rest of the OS: pure x86-64 assembly, statically linked,
ring 0, direct calls.

Legend: ✅ done · ◐ exists but unproven · ☐ planned. Line counts ±50%.

---

## 1. Requirements

| Area | Requirement |
|---|---|
| Correctness | All four clock modes, chip-select timing, word sizes, single, dual and quad data lines where the controller has them |
| Throughput | DMA for transfers above a small size; tens of MB/s on flash reads |
| Safety | **Firmware flash is read-only by default.** Writing it needs an admin capability, a signed image and a confirmation |
| Observability | Buses, devices, transfer counts and errors in `/sys/dev/spi/` |

---

## 2. Target hardware

| Controller | Where | Phase |
|---|---|---|
| Intel LPSS SPI (with DMA) | Intel laptops with SPI-HID devices or fingerprint readers | 1 |
| AMD SPI controller | AMD machines (mostly the firmware flash) | 2 |
| Chipset flash controllers (Intel and AMD) | Firmware flash access | 3 |

---

## 3. Components

- ☐ Controller drivers: Intel LPSS with DMA, AMD SPI
- ☐ Transfer interface: `spi_xfer(dev, segments)` with full-duplex,
  write-then-read and multi-line transfers; chip-select control
- ☐ Device discovery from ACPI `SpiSerialBus` resources
- ☐ Generic serial bus operation region for AML on SPI devices
- ☐ SPI-HID transport hand-off to `lib/input/spi_hid`
- ☐ Flash access: identify the chip (SFDP), read, and (policy-gated) erase
  and write; used for firmware version reporting and signed firmware
  updates
- ☐ Tools: `spi` command to list buses and devices, read flash identity
- ☐ Hardening: transfer timeouts, controller reset, fuzzed device replies

---

## 4. Phases

| Phase | Work | Lines |
|---|---|---|
| 1 | Intel LPSS controller, transfer interface, ACPI discovery, SPI-HID hand-off | ~1 500 |
| 2 | AMD SPI controller, generic serial bus region | ~800 |
| 3 | Flash identity and reading; policy-gated writes; tools; hardening | ~1 200 |
| **Total** | | **~3 500** |

Phase 1 is needed by input Phase 7 (SPI-HID).

---

## 5. Consumers

| Consumer | Devices |
|---|---|
| `lib/input` | SPI-HID keyboards and touchpads |
| `security/` | Fingerprint readers (later), TPMs on SPI |
| Firmware update (later) | System flash |

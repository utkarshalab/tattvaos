# gpio — Roadmap

**Part of:** Utkarsha OS, `lib/io/gpio` — GPIO and pin controllers
**Status:** Phase 1 core written and host-tested (2026-11-07): AMD controller,
pin interface, interrupts with storm detection, debounce (`gpio.asm`). Not
yet run on hardware; kernel glue and ACPI discovery still to come
**Decided 2026-11-06:** GPIO lives here (input decision I2)

GPIO pins carry interrupts and control lines for devices that are not on
PCI: the touchpad's interrupt, Bluetooth power and wake lines, touchscreen
reset, Wi-Fi kill switches, camera privacy LEDs, and ACPI events wired to
pins. `lib/io/gpio` drives the pin controllers and gives every other driver
one interface for pins and pin interrupts.

Built like the rest of the OS: pure x86-64 assembly, statically linked,
ring 0, direct calls.

Legend: ✅ done · ◐ exists but unproven · ☐ planned. Line counts ±50%.

---

## 1. Requirements

| Area | Requirement |
|---|---|
| Latency | Pin interrupt to the consumer's handler in under 20 µs |
| Correctness | Edge and level interrupts, both polarities, both edges, debounce, wake; no lost edges, no repeated level interrupts |
| Safety | A pin stuck active (interrupt storm) is masked and reported; other pins keep working |
| Ownership | Each pin has one owner, from ACPI resources; a driver cannot drive a pin it does not own |
| Power | Pin and interrupt state survive sleep; wake pins work in low-power idle |
| Observability | Every pin's owner, mode, level and interrupt count in `/sys/dev/gpio/` |

---

## 2. Target hardware

| Controller | Where | Phase |
|---|---|---|
| **AMD GPIO** (`AMDI0030`) on this machine: one MMIO bank of pin registers, one shared interrupt line | All AMD Ryzen laptops and desktops | 1 |
| Intel pin controllers: several "communities" per chip, layouts differ by generation | Intel laptops and desktops | 3 |
| Other ACPI GPIO controllers found on tested machines | — | 4 |

---

## 3. Components

- ☐ Controller drivers: AMD first, then Intel by generation (one table per
  generation of pad layouts and community offsets)
- ☐ Pin interface: `gpio_get(desc)`, `gpio_set`, `gpio_dir`, `gpio_pull`,
  `gpio_debounce`, `gpio_irq(desc, mode, handler)`, `gpio_wake`
- ☐ Pin interrupts: chained from the controller's shared line to one
  handler per pin; edge, level, both edges, polarity, masking, storm
  detection
- ☐ Pin control: function selection (muxing) and pin configuration from ACPI
  pin function and pin configuration resources
- ☐ ACPI glue: `GpioInt` and `GpioIo` resources, GPIO operation regions for
  AML, `_AEI` and `_EVT` events (with `lib/io/acpi`)
- ☐ Sleep: save and restore, wake pin setup for S0 low-power idle and S3
- ☐ Firmware bugs: wrong polarity or trigger in ACPI tables, fixed through
  a quirk table
- ☐ Tools: `gpio` command to list pins, owners, levels and counts

---

## 4. Phases

| Phase | Work | Lines |
|---|---|---|
| 1 | ◐ AMD controller, pin interface, interrupts, debounce (for the touchpad); kernel glue still to come | ~2 000 |
| 2 | ACPI glue: resources, operation regions, `_AEI` events; wake and sleep | ~1 000 |
| 3 | Intel controllers, all supported generations | ~3 000 |
| 4 | Pin control, quirks, tools, hardening (storms, fault injection) | ~1 000 |
| **Total** | | **~7 000** |

Phase 1 is part of input Phase 3 (the built-in touchpad).

---

## 5. Consumers

| Consumer | Uses |
|---|---|
| `lib/input` (I²C-HID touchpads, touchscreens, pens) | Interrupt pins, reset pins |
| `lib/ubt` | Bluetooth power-enable, reset, host-wake and device-wake pins |
| `lib/io/acpi` | GPIO operation regions, GPIO-signalled events |
| `lib/io/i2c` | Bus recovery (toggling the clock pin) |
| `lib/unet` | Wi-Fi kill and wake pins |
| `lib/uvid` | Camera privacy LED and shutter switch |

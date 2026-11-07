# lib/input — input devices

Turns input hardware into events and hands them to canvas through
`ut_input_register_callback`. Plan and boundaries: [ROADMAP.md](ROADMAP.md).

## What exists (Phases 0 and 1)

| File | What it does |
|---|---|
| `input.inc` | Event record (24 bytes), device information (64 bytes), constants |
| `input.asm` | The whole library as one include; needs nothing from the kernel |
| `core/hooks.asm` | Replaceable clock and port I/O (the kernel sets the clock; tests replace port I/O) |
| `core/dev.asm` | Device list: up to 32 devices, IDs from 1 |
| `core/event.asm` | Event ring (256 events), `input_pump`, and `ut_input_register_callback`, `ut_input_unregister_callback`, `ut_input_device_info`, `ut_input_grab` |
| `ps2/i8042.asm` | PS/2 controller: detection, self-test, translation, IRQ 1 work |
| `ps2/kbd.asm` | PS/2 keyboard: reset, scan code set 1 decoding, repeat suppression, lock-key LEDs |
| `hid/boot.asm` | Boot keyboard and mouse reports into events, and `hid_usage_key`, the keyboard usage → keycode table every HID transport uses |
| `hid/hid.inc`, `hid/parse.asm` | The shared HID core: `hid_parse` turns a report descriptor into fields; `hid_get` reads an element's value from a report; `hid_find_usage` finds the element with a usage; `hid_report_bits` gives a report's length |
| `i2c_hid/i2c_hid.asm` | I²C-HID devices: `i2c_hid_probe` brings one up (touchpads switched to multi-touch); `i2c_hid_attention` marks it from its interrupt; `i2c_hid_service` turns waiting reports into events on the fiber |
| `kernel.asm` | Kernel glue: input fiber, IRQ 1 handler, start-up (`input_kernel_prepare`, `input_kernel_start`) |
| `kernel_acpi.asm` | The ACPI lid (a switch device) and power and sleep buttons (keys) as input devices |
| `kernel_touchpad.asm` | Kernel glue for the built-in touchpad: `input_touchpad_init` finds it through ACPI, attaches its I²C and GPIO controllers, routes the interrupt and probes it |

## How events flow

1. IRQ 1 → `input_ps2_isr` → `i8042_irq` reads each byte → `ps2_kbd_byte`
   decodes it → `input_post` puts a key event in the ring.
2. The input fiber runs `input_pump`, which calls the registered callback
   once per event with `RDI` = the record and `RSI` = the cookie. The
   callback never runs inside an interrupt.

Keycodes are the numbers canvas's keymaps use: set 1 make codes for the
base keys (A = 30), and 96 and up for keys behind an 0xE0 prefix
(Right Ctrl = 97, Up = 103, Super = 125).

## Tests

```
sh lib/input/tests/run_tests.sh
```

Assembles the library, links it into a shared object, and drives it from
Python:

| Suite | Checks | Against |
|---|---|---|
| `test_input.py` | 66 | The event core and a simulated PS/2 controller and keyboard (`sim_ps2.py`) |
| `test_boot.py` | 28 | The usage → keycode table; boot keyboard reports (presses and releases in any order, modifiers, ErrorRollOver, lock keys, six keys, unknown usages, short reports); boot mouse reports |
| `test_hid.py` | 50 | Report descriptors built by `hid_gen.py`, and mutated ones |
| `test_i2c_hid.py` | 30 | A simulated I²C-HID touchpad and mouse |
| `test_acpi_input.py` | 7 | `kernel_acpi.asm`: the devices, the lid at start-up and when it opens, the buttons |
| `test_touchpad_kernel.py` | 20 | `kernel_touchpad.asm` end to end (built by `tp_stub.asm`): firmware tables, simulated GPIO and I²C controllers and touchpad, and firmware that does not fit |

`kernel.asm` is checked by the kernel build.

Events posted from a fiber go through `input_post_safe`, which turns
interrupts off around the ring's lock (hooks `input_irq_off_fn` and
`input_irq_restore_fn`; the tests replace them).

## Not yet

- Not run on QEMU or on real hardware.
- PS/2 mouse and touchpads (Phase 4), USB HID (Phase 2).
- The touchpad path has not run on hardware: QEMU has no I²C-HID touchpad,
  so the first real test is a boot on the laptop.
- Power button and lid: they need the ACPI interpreter on this machine.

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
| `hid/hid.inc`, `hid/parse.asm` | The shared HID core: `hid_parse` turns a report descriptor into fields; `hid_get` reads an element's value from a report; `hid_find_usage` finds the element with a usage; `hid_report_bits` gives a report's length |
| `kernel.asm` | Kernel glue: input fiber, IRQ 1 handler, start-up (`input_kernel_prepare`, `input_kernel_start`) |

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
Python against a simulated PS/2 controller and keyboard
(`tests/sim_ps2.py`). `kernel.asm` is checked by the kernel build.

## Not yet

- Not run on QEMU or on real hardware.
- PS/2 mouse and touchpads (Phase 4), HID core and USB (Phase 2), the
  built-in I²C touchpad (Phase 3).
- Power button and lid: they need the ACPI interpreter on this machine.

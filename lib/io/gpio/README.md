# lib/io/gpio — GPIO pins and pin interrupts

Plan: [ROADMAP.md](ROADMAP.md).

## What exists (Phase 1, host-tested)

`gpio.asm` drives AMD GPIO controllers (ACPI `AMDI0030` and relatives):

| Call | What it does |
|---|---|
| `gpio_amd_attach(base, pins)` | Adds a controller (up to 2, up to 256 pins), returns its number |
| `gpio_claim(ctrl, pin, owner)` / `gpio_release` | Takes or gives back a pin; release also turns its interrupt off |
| `gpio_get(ctrl, pin)` | The input level; anyone may read |
| `gpio_set`, `gpio_direction`, `gpio_pull`, `gpio_debounce`, `gpio_wake` | Pin settings; only the owner |
| `gpio_irq_setup(ctrl, pin, owner, mode, handler, cookie)` | Level or edge, high, low or both edges; `handler(cookie, pin)` runs in interrupt context |
| `gpio_irq_unmask` | Re-arms a level pin after its device has been serviced, or a pin masked as a storm |
| `gpio_irq_disable` | Turns a pin's interrupt off |
| `gpio_irq(ctrl)` | The controller's interrupt: dispatch, clear, end of interrupt |

Rules:

- Changing a pin needs its owner: an unclaimed pin is `-EINVAL`, another
  owner's is `-EBUSY`.
- Settings never write 1 to the write-1-to-clear status bits, so they
  cannot lose a pending interrupt.
- A level-triggered pin is masked before its handler runs. Unmasking clears
  any status latched meanwhile, so a released line does not fire a stale
  interrupt, and a line still asserted fires again.
- An interrupt nobody handles is turned off and counted (`gpio_spurious`).
- A pin interrupting more than 10 000 times in a second is masked and
  counted (`gpio_storms`); the other pins keep working.

Register access goes through `gpio_read32_fn` and `gpio_write32_fn`; the
storm clock through `gpio_clock_fn`.

## Not yet

- Checked against real hardware: the register layout is the AMD one as
  documented for this controller family, but nothing has run on the
  laptop yet.
- Kernel glue for the touchpad's controller lives in
  `lib/input/kernel_touchpad.asm` (with `ioapic_route_gsi` for its
  level, active-low interrupt); general discovery of every controller is
  still to come.
- Intel controllers, pin muxing, the AML GPIO operation region, `_AEI`
  events.

## Tests

```
sh lib/io/gpio/tests/run_tests.sh
```

`tests/sim_amd.py` simulates the controller (write-1-to-clear status,
summary registers, end of interrupt, level and edge latching);
`tests/test_gpio.py` runs 65 checks against it.

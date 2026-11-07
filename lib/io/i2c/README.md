# lib/io/i2c — I²C host controllers

Plan: [ROADMAP.md](ROADMAP.md).

## What exists (Phase 1, host-tested)

`i2c.asm` drives DesignWare I²C controllers (AMD `AMDI0010` and
relatives):

| Call | What it does |
|---|---|
| `i2c_dw_attach(base, clock_khz)` | Checks the component type register, adds the controller (up to 4), starts it at 400 kHz when the clock is known |
| `i2c_dw_set_speed(ctrl, hz, hcnt, lcnt, hold)` | Standard (up to 100 kHz), fast, or fast plus (up to 1 MHz). Counts from ACPI when given; otherwise worked out from the clock and the bus's minimum high and low times |
| `i2c_xfer(ctrl, msgs, count)` | One transfer: messages to one target joined by repeated starts, a stop at the end; 7- or 10-bit addresses |
| `i2c_write_read(ctrl, addr, wbuf, wlen, rbuf, rlen)` | The usual register read; with no read it is a plain write, with no write a plain read |

Transfers are polled: they run on a fiber, never in an interrupt. Received
bytes are taken while commands are still being sent, so reads of any
length work whatever the FIFO size. Every wait is bounded.

Errors: `-ENXIO` when nobody answers at the address, `-EIO` for other
aborts (data not acknowledged...), `-ETIMEDOUT` (bus never idle,
controller never turning off, FIFO never having room), `-EINVAL`. Aborts
and timeouts are counted (`i2c_aborts`, `i2c_timeouts`), and the last
abort source is kept.

Register access goes through `i2c_read32_fn` and `i2c_write32_fn`.

## Not yet

- Checked against real hardware.
- Kernel glue: finding the controllers through ACPI (`_CRS` for the
  registers, `SSCN` and `FMCN` for timing), mapping them.
- Interrupt-driven transfers, bus recovery through GPIO, Intel LPSS with
  DMA, SMBus, I3C, the generic serial bus region for AML.

## Tests

```
sh lib/io/i2c/tests/run_tests.sh
```

`tests/sim_dw.py` simulates the controller with devices on its bus;
`tests/test_i2c.py` runs 39 checks against it.

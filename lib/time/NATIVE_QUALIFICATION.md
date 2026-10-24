# Native calendar and clock qualification

Validated on 2026-10-24. Both app adapters execute shared `lib/time` reads and
`lib/cal` civil conversion. App code and native test harnesses are NASM; Python
drives differential tests and QEMU, without replacing the native implementation.

## Host checks

- `make -C apps/calender test`: PASS (6000 civil cases, 1500 month grids,
  event queries/updates, UTF-8 and atomic failure handling).
- `make -C apps/clock test`: PASS (5000 stopwatch operations, 2000 countdowns,
  1000 alarm polls, callback failures, overflow and notification backpressure).
- Native assembly ABI integration: PASS.
- Actual-library wiring: PASS (800 RTC/monotonic/civil paths; BCD/binary,
  12/24-hour, century fallback, invalid dates, battery/frozen-clock rejection,
  stuck update flags, continuous rollover and pre-initialization failures).
- Calculator, Uedit model/PTY and Ush complete host suites: PASS.
- Ush static bundle relocation, section ownership and corrupt metadata: PASS.

## Production kernel

`make -C boot img uefi` and `sh boot/tests/test_image_integrity.sh`: PASS.

Kernel size: 9,995,216 bytes. SHA-256:
`c617e46e6652c6de7d6b2c1f3a69b0586890dc423c4f1494945eda686d177af3`.

Run `python3 boot/tests/test_ush_qemu.py` with each option set:

| Options | Result |
|---|---|
| `--firmware bios --native-time-test` | PASS |
| `--firmware ovmf --smp 4 --native-time-test` | PASS |
| `--firmware ovmf --strict-nx --native-time-test` | PASS |

QEMU TCG uses CPU `max`, 512 MiB RAM, and RTC base `2026-10-24T00:00:00`.
The kernel startup probe calls `uclock_read_native`, `ucal_now`,
`uclock_local_now` and `ucal_month_now`. Tests require a valid UTC epoch and
local date/time `2026/10/24 5:45` for offset +20,700 seconds. Each guest also
checks shell editing/history, interrupts, background redraw, chaining,
calculator execution, cooperative sleep and scheduler progress after exit.
The BIOS gate verifies that the boot image remains unchanged.

Transcripts are generated under `apps/ush/build/qemu-*-native-time.log` with
matching stderr files; generated artifacts are not committed.

## Limits

These are focused emulator checks, not physical-hardware certification or the
entire boot regression matrix. RTC wall time has one-second precision and is
interpreted as UTC. The checked APIs do not certify legacy `tm_to_epoch`,
`epoch_to_tm` or `lib/cal/unix.asm` paths. Canvas/UI, audio, persistent events
and alarm delivery scheduling remain separate work. The kernel probe exercises
the source/date adapters; model suites cover event/alarm state machines.

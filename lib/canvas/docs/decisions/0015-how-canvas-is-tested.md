# Decision 0015: How Canvas Is Tested

**Status**: Accepted (2026-11-09)
**Date**: 2026-11-09
**Phase**: P0 (FND-03, FND-10, ECO-05)

## Context
Canvas is assembly running on a kernel that does not yet export most of what
it needs, and booting the kernel in an emulator for every change is not
available yet (QA-18). Tests still have to show that each behaviour works and
that a change which breaks it is caught.

## Options
| Option | Problem |
|---|---|
| A. Test only on Utkarsha OS, booted | Slow, and blocked on kernel exports and an emulator setup |
| B. Test on the development machine through a stand-in for the kernel | The stand-in can differ from the kernel |
| C. Review without tests | Assembly breaks silently |

## Decision
**Option B, with Option A to follow (QA-18).**

- **The host shim.** `tests/host/ut_host.asm` stands in for every `ut_*`
  import. Unit suites (`tests/unit/test_*.asm`) link against the same objects
  as the UBF and run as ordinary programs. Anything a test needs from the
  kernel (a device's info, a second framebuffer) is added there and kept to
  the layouts `KERNEL_NEEDS.md` gives.
- **`make check` is the gate.** It builds every image in debug and release
  and runs:
  - the layout checks (field widths, W^X, position independence, symbol
    consistency);
  - every host suite;
  - the decoders against a reference decoder;
  - the two fuzzers;
  - the UBF loaded and run to its first frame.

  A change is pushed only when it passes.
- **Mutation checks.** For each new behaviour, its key logic is removed or
  changed once and the test that covers it must fail. One that does not is
  strengthened, or the logic is shown to be redundant and removed.
- **Fuzzing with fixed seeds.**
  - `test_fuzz` covers the wire and input; `fuzz_media.py` covers the
    decoders.
  - Both start from fixed seeds, so a failure repeats.
  - A crash or a hang fails the check, and an input that fails becomes a
    regression test.
- **Golden frames** by checksum for the compositor's output.
- **No emulator runs for now.** Booting in an emulator is left until the
  machine it runs on can take it; tests that need real hardware wait.

## Consequences
- What the shim does not model (timing, interrupts, real devices) is not
  tested; KERNEL_NEEDS records what the kernel must do instead.
- `test_runner.img`, built from the same unit sources, links without the
  shim. So a test must not use symbols only the shim defines; such state
  lives in Canvas (for example `Server.suspends`).

## Related
- `docs/definition-of-done.md`; ROADMAP FND-03, FND-10, QA-18, QA-19
- `Makefile` targets `check`, `fuzz`, `symbol-check`

## Revisit Criteria
When QA-18 (booting the real kernel in an emulator per commit) is possible:
the host shim stays for speed, the emulator becomes part of the gate.

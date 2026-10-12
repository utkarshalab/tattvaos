# Canvas Conformance Suite (C33)

Black-box protocol tests in `tests/cts/`. Any Canvas build or third-party
client can run them against a live server.

## Suites

| Suite | File | Covers |
|-------|------|--------|
| core | `cts_core.asm` | connect, capability grants, sync serials, error objects |
| surface | `cts_surface.asm` | create/destroy, attach, damage, commit |
| sync | `cts_sync.asm` | fences/timelines, no round-trips on hot path |
| present | `cts_present.asm` | frame callbacks fire exactly once per commit |
| output | `cts_output.asm` | output enumeration |
| input | `cts_input.asm` | event delivery to focused surface |
| shell | `cts_shell.asm` | toplevel create, configure/ack |
| data | `cts_data.asm` | clipboard set/get round-trip |
| text | `cts_text.asm` | input-method enable/commit |
| security | `cts_security.asm` | privileged caps invisible without grants |
| governance | `cts_governance.asm` | server survives churn, quotas enforced |

## Running

```
make cts        # builds build/img/cts_runner.img
./tests/run_cts.sh
```

All suites must report `failed=0`. A release tag requires a clean CTS run
on reference hardware, recorded in the release notes.

## Writing New Tests

- One `TEST_CASE` per normative sentence in `docs/protocol/`.
- Tests use only the public client ABI (`inc/canvas_client.inc`).
- A test that needs privileged caps must first assert denial, then (with a
  granted token) assert success — never assume ambient authority.

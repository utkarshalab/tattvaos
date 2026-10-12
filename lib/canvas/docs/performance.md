# Canvas Performance Targets (C32)

Measured on reference hardware, recorded under `tests/bench/results/`.
Placeholders below are replaced with real numbers at C32 sign-off.

| Metric | Target | How measured |
|--------|--------|--------------|
| Idle CPU | zero wakeups with no damage and no timers | `bench_idle` (waitset 100ms quiescence) |
| Input to photon | next vblank after the event (direct scanout) | `bench_latency` (synthetic event at vblank-ε) |
| Server resident memory | under 8 MB idle with 2 outputs (excl. client buffers) | `bench_memory` (`accounting_snapshot`) |
| `canvasd` image size | under 1 MB | `make size` (stripped) |
| Cold start to first frame | under 100 ms after Canvas init | timer from `canvasd_init` to first `flip` |
| Hot-path round trips | none for commit, damage, frame callbacks | protocol log audit (`protolog`) |
| Scale | 256 clients / 1,000 surfaces, no dropped frames | `soak_churn` + frame timeline |

## Method

See `benchmark-method.md`. One command: `make bench` builds
`bench_runner.img`; results are appended to `tests/bench/results/<hw>.md`.

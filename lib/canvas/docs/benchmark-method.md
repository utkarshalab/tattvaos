# Canvas Benchmark Method (C32)

## Environment

- Bare metal reference machine (record CPU, RAM, display, kernel rev).
- `performance` CPU governor equivalent: fixed clocks, no turbo variance.
- Single active output at native mode unless the benchmark says otherwise.
- No remote viewers, no recording, default `standard` trust profile.

## Procedure

1. `make bench` → `build/img/bench_runner.img`.
2. Boot Tattva with `bench_runner.img` as init; collect serial output.
3. Each benchmark prints one line: `<name>: <value> <unit>`.
4. Append the block to `tests/bench/results/<machine>.md` with date + rev.
5. Re-run 3×; report median. Variance >10% → investigate, do not tune blindly.

## Benchmarks

| Binary | Measures | Pass criteria |
|--------|----------|---------------|
| `bench_idle` | waitset wakeups over 1s idle | 0 wakeups |
| `bench_latency` | synthetic input → presented frame | ≤ 1 vblank |
| `bench_compose` | `compositor_composite` ns/frame | fits vblank budget |
| `bench_memory` | resident KB via `accounting_snapshot` | < 8 MB server |

## Tuning Rules

- Tune hot paths only (blend, damage, commit, flip).
- Every tuning lands with before/after numbers in the results file.
- No tuning that breaks determinism (golden frames must still match).

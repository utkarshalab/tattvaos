# Project Structure

Target: Tattva OS only. x86-64 first; AArch64 and RISC-V 64-bit reserved. NASM now, utasm later. Zero third-party dependencies. Every directory has a README.md stating its purpose.

```
bench/
bootstrap/
docs/
  adr/
  manual/
  plan/
  specs/
  standards/
examples/
fuzz/
include/
packaging/
  images/
  ulf/
scripts/
sim/
src/
  arch/
    aarch64/
    riscv64/
    x86_64/
  bridge/
  cli/
  core/
  graph/
  ide/
  kernels/
    aarch64/
    avx2/
    avx512/
    riscv64/
    scalar/
  merge/
  oplog/
  policy/
  server/
  store/
  sync/
  ufs/
tests/
  conformance/
  differential/
  golden/
  unit/
  vectors/
tools/
```

## Layers

- `include/`, `src/core`, `src/arch`, `src/kernels`: foundation (macros, memory, per-architecture code and SIMD).
- `src/ufs`, `src/store`, `src/graph`: storage on UFS.
- `src/merge`, `src/oplog`: version-control logic.
- `src/sync`, `src/bridge`: networking and git interop.
- `src/server`, `src/policy`: server and enterprise layer.
- `src/cli`, `src/ide`: user-facing interfaces.
- `tests`, `fuzz`, `sim`, `bench`: quality gates.
- `docs`: plan, Phase 0 specs, standards, decision records, manual.
- `packaging`: ULF packages and bootable Tattva OS images.

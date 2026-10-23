# ADR 0001: Target and Assembler

- Status: Accepted

## Decision

- Target: Utkarsha OS only. No other operating systems.
- Architectures: x86-64 first. AArch64 and RISC-V 64-bit have reserved places in the tree (`src/arch`, `src/kernels`) but no work starts until x86-64 is done.
- Assembler: NASM for now; migrate to utasm later. NASM supports x86 only, so AArch64 and RISC-V work depends on utasm.

## Consequences

- No OS abstraction layer and no ABI definitions; the VCS uses Utkarsha OS and UFS directly.
- Architecture-specific code is isolated under `src/arch/<arch>` and `src/kernels/<arch>`, so adding an architecture does not touch shared modules.
- Source files use NASM syntax (`.asm`, `.inc`) until the utasm migration.

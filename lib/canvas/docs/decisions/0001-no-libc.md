# Decision 0001: No libc, No Standard Library

**Status**: Accepted
**Date**: 2026-10-12
**Phase**: C0

## Context
Canvas runs on Tattva OS, a bare-metal x86-64 unikernel. There is no POSIX layer, no C runtime, no dynamic linker.

## Decision
Canvas is written entirely in **x86-64 NASM assembly** with:
- Direct Tattva syscalls (via `inc/tattva.inc` bindings)
- No `libc`, no `libm`, no `libstdc++`
- No C compiler involved in Canvas build
- All data structures, algorithms, string handling, memory management implemented in-house

## Rationale
| Factor | With libc | Without libc (Chosen) |
|--------|-----------|----------------------|
| Binary size | ~500 KB minimum | < 100 KB (canvasd target < 1 MB) |
| Attack surface | Large (decades of CVEs) | Minimal — only our code |
| Performance predictability | Hidden allocations, locks | Every cycle accounted for |
| Bare-metal suitability | Requires porting effort | Native |
| Debugging | Complex runtime | Direct, no runtime magic |

## Consequences
- **More code to write**: Arena, string, hash, map, vec, ring, config parser, logger
- **No printf/malloc/threads**: Must implement equivalents (`fmt.asm`, `arena.asm`, `tv_task.asm`)
- **Build system**: Custom Makefile, no CMake/autotools
- **Testing**: Custom test harness (C3), no `gtest`/`check`

## Implementation
- `inc/abi.inc` — Calling convention macros
- `inc/macros.inc` — Assert, trap, align, bounds-check
- `src/core/` — All core library modules (C1)
- `src/tattva/` — Thin syscall wrappers (C0, C5, C9, C10, C12, C18, C26)

## Related
- `architecture.md` §1, §14
- `tattva-contract.md` — Exact syscall signatures
- Decision 0002 (pixel format), 0004 (handles)

## Revisit Criteria
If Tattva adds a POSIX compatibility layer with acceptable overhead, re-evaluate. Unlikely.
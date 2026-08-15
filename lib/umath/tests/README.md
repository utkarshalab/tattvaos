# tests — umath Test Harness

**Module:** `tests/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Test harness and test cases for umath. `boot/Makefile` explicitly excludes
every `tests/` directory (`-not -path '*/tests/*'`) from the kernel's
source glob — this directory is never assembled into `kernel.bin`, it has
its own separate build/run path, matching every other `tests/` directory
already established elsewhere in the repo (`unet/`, `crypto/`, etc. per
`boot/Makefile`'s comment on the subject).

The verification approach `math_fn/README.md` documents — `ld -shared` a
file into a `.so`, drive it from Python via `ctypes`, compare against a
reference implementation — was done ad hoc per-file during development
rather than checked in as a running suite. This folder is where that
should eventually live as an actual, re-runnable harness rather than a
one-off methodology repeated by hand each time.

## Planned scope

- A build step that assembles individual umath `.asm` files as standalone
  ELF objects (or the natural multi-file combinations, e.g. `pow_f32.asm`
  needs `log_f32.asm`+`exp_f32.asm` in the same assembly pass) and links
  them as shared objects for host-side testing
- Reference-value test cases per module, starting with `math_fn/`'s
  already-exercised sqrt/exp/log/pow test vectors
- Ideally runs on the host (Linux/WSL, per this project's build setup)
  without needing QEMU — the whole point is fast iteration during
  development, not boot-testing

## Dependencies (anticipated)

```
tests/ is excluded from the kernel image entirely (see boot/Makefile);
it depends on whatever host toolchain (nasm, ld, a Python or similar
driver) is available in the development environment, not on anything
inside the kernel build.
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

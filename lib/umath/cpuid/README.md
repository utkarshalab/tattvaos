# cpuid — umath CPU Feature Detection

**Module:** `cpuid/`
**Status:** Implemented — detection, a restrict mask for testing, and SSE2 fallbacks for every faster instruction umath uses.
**Part of:** umath — unified math library

---

## Purpose

umath runs on **any x86-64 CPU**. The x86-64 baseline guarantees SSE2 and
nothing else. Faster code paths use later extensions:
SSE4.1 `roundsd`/`pminsd`, BMI2 `pdep`, AVX2 memcpy and so on. Each one is
checked at run time. When the CPU (or the OS) lacks the extension, umath
does the same operation with baseline instructions. It is slower but gives
bit-identical results. Nothing faults with #UD.

Without this module, two kinds of failure were possible:

- **Crash (#UD):** SSE4.1/SSSE3/SSE4.2 instructions, BMI2, AVX/AVX2/AVX-512,
  and PREFETCHW on early 64-bit Intel parts.
- **Silently wrong results:** without LZCNT/BMI1, `lzcnt`/`tzcnt` decode
  as the older `bsr`/`bsf`. These do not fault. They return a bit index
  instead of a count, so `clz(1)` came back as 0, not 63.

## Files

- `cpuid.asm` — detection and the public API.
- `fallback.asm` — the `um_*` instruction macros, `um_need`, and the
  emulation helpers. Every umath file that uses an extension includes it.

## API

| Function | Args | Returns |
|---|---|---|
| `umath_cpu_init` | — | `rax` = effective feature mask (idempotent) |
| `umath_cpu_features` | — | `rax` = effective mask (detects first if needed) |
| `umath_cpu_has` | `edi` = feature bit | `eax` = 1 / 0 |
| `umath_cpu_restrict` | `rdi` = allowed mask (`-1` all, `0` SSE2 only) | `rax` = new effective mask |

Feature bits:

```text
 0 SSE3    1 SSSE3   2 SSE4.1   3 SSE4.2   4 POPCNT   5 LZCNT
 6 BMI1    7 BMI2    8 AVX      9 AVX2    10 FMA     11 AVX-512 (F+BW+VL)
12 PREFETCHW
```

AVX, AVX2, FMA and AVX-512 count as present only when the OS has enabled
their register state. That means CPUID.OSXSAVE is set and XGETBV shows
XCR0 bits 1–2 (and 5–7 for AVX-512). Without that state, every ymm/zmm
instruction raises #UD, even on hardware that has AVX.

`umath_cpu_restrict` can only remove features: a bit the CPU lacks stays
off. It serves two purposes:
- testing the fallbacks on a modern machine;
- for a kernel, holding umath to the state it has actually enabled.

Calling `umath_cpu_init` is optional. The first check that finds a feature
byte still at 0 runs detection itself.

## How the checks work

**Single instructions** (`um_roundsd`, `um_popcnt`, `um_pdep`, … — 14
macros, 352 sites across 38 files). Each one tests one cached byte, such
as `umath__has_sse41`:
- If the feature is present, the macro runs the native instruction. The
  cost is a compare and a predicted branch.
- If not, it calls an emulation helper that preserves every register
  except the destination and the flags. (Flag liveness was checked at
  every call site.)

What each helper emulates:
- **Rounding:** uses `(|x| + 2^52) − 2^52` for round-to-nearest-even, then
  ±1 for floor/ceil/trunc, then puts the sign back. ±0, ±Inf, NaN
  quieting and |x| ≥ 2^52 match `roundsd` exactly.
- **`popcnt`/`lzcnt`/`tzcnt`/`pdep`/`pext`:** bit loops.
- **`pminsd`/`pmaxsd`/`pabsd`/`pcmpgtq`:** per-lane loops.

**Whole routines** (`um_need umath__has_X, fallback`). The AVX2/AVX-512
routines check once at entry and jump to a narrower version with the same
arguments and results:

| Routine | Without the feature |
|---|---|
| `memcpy/memset/memzero_avx512` | → `_avx2` (→ `_sse`) |
| `memcpy/memmove/memset/memzero/memcmp_avx2` | → `_sse` |
| `memfill_pattern4/8/32` | qword / SSE2 loops |
| `abs_i64_array/_inplace/_sat_array` | scalar loops |
| `min_i64_array/_inplace_clip` | scalar `cmov` loops |
| `prefetch_w`, `prefetch_range` / `_block_transposed` hint 4 | read-intent `prefetcht0` |
| `bit512_load/store/zero/all_ones` | return without effect (no zmm register to use) |

**Rewritten outright** (SSE2 is just as fast):
- `bit512_and/or/xor/not` (four xmm quarters);
- `exp_f64`'s `pmovsxdq` (→ `psrad` + `punpckldq`);
- `reduce_sum_i32/u32` (→ unpack with sign/zero, `pshufd`);
- `bit2`'s `blsr` (→ `lea` + `and`).

## Verification

- `tests/run_tests.sh` runs the whole suite twice: natively, then with
  `UMATH_CPU_MASK=0` (SSE2 only). Every reference test therefore also
  checks every fallback.
- `tests/test_cpu.py`:
  - checks detection against Linux's `/proc/cpuinfo` flags;
  - checks the restrict/has API;
  - loads a second copy of the library restricted to the baseline and
    compares every rounding-heavy float function bit for bit: sin, cos,
    exp, pow, and floor/ceil/round/trunc in every form. Inputs include
    raw bit patterns and signalling NaNs.
- A static scan of every source line found no instruction beyond SSE2
  that can run without one of these checks.

## TattvaOS note

The kernel enables SSE (CR4.OSFXSR) but not XSAVE (CR4.OSXSAVE/XCR0).
Under TattvaOS, umath therefore reports no AVX and takes the SSE2/SSE4
paths, even on AVX hardware. That is correct and safe.

Enabling AVX in the kernel would be a separate step:
- set CR4.OSXSAVE and XCR0 in `kernel/arch/x86_64/cpu.asm`;
- save and restore ymm/zmm state on context switch.

## Dependencies

```text
cpuid/ depends on:
  → nothing (Tier 0, raw CPUID/XGETBV)

cpuid/ is depended on by:
  → bits/, math_fn/, memory/, scalar/ (via fallback.asm)
```

`dtype/dtype_support.asm` still keeps its own private CPUID cache. Moving
it onto this module is a possible follow-up.

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

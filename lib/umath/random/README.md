# random — umath Fast Pseudo-Random Number Generation

**Module:** `random/`
**Status:** Implemented — xoshiro256** core, splitmix64 seeding, uniform [0,1) samplers
**Part of:** umath — unified math library

## Purpose

Fast, non-cryptographic PRNGs for numerical use: weight initialization, dropout-style masking, Monte Carlo sampling, stochastic rounding. Explicitly *not* `lib/urand/`'s CSPRNG — a math-workload PRNG wants speed and statistical quality over unpredictability.

## Files

```
random/
├── xoshiro256.asm   ← xoshiro256** 64-bit PRNG core (4-word state: s0,s1,s2,s3)
├── seed.asm         ← splitmix64 u64 seeding + lib/urand entropy seeding
└── uniform.asm      — uniform [0,1) samplers, scalar + array variants
```

## Calling Convention

System V AMD64 ABI throughout. State is a `random_state_t` (32 bytes: 4 × u64) passed by pointer in `rdi`.

| Function | Args | Returns | Clobbers |
|----------|------|---------|----------|
| `umath_random_xoshiro256_next` | `rdi = *state` | `rax = u64` | rcx, r8, r9 |
| `umath_random_xoshiro256_seed_from_u64` | `rdi = *state, rsi = seed u64` | state filled | rcx, r8 |
| `umath_random_xoshiro256_seed_from_urand` | `rdi = *state, rsi = urand_fill` | `rax = 1/0` | all SysV caller-saved |
| `umath_random_uniform_f32` | `rdi = *state` | `xmm0 = f32 [0,1)` | rax, rcx, r8, r9 |
| `umath_random_uniform_f64` | `rdi = *state` | `xmm0 = f64 [0,1)` | rax, rcx, r8, r9 |
| `umath_random_uniform_f32_range` | `rdi = *state, xmm0 = lo, xmm1 = hi` | `xmm0 = f32 [lo,hi)` | rax, rcx, r8, r9, xmm1, xmm2 |
| `umath_random_uniform_f64_range` | `rdi = *state, xmm0 = lo, xmm1 = hi` | `xmm0 = f64 [lo,hi)` | rax, rcx, r8, r9, xmm1, xmm2 |
| `umath_random_fill_uniform_f32` | `rdi = *state, rsi = *dst, rdx = count` | array filled | rax, rsi, r8, r9, xmm0 |
| `umath_random_fill_uniform_f64` | `rdi = *state, rsi = *dst, rdx = count` | array filled | rax, rsi, r8, r9, xmm0 |

**Seeding:** `seed_from_u64` fills s0..s3 with the first four splitmix64 outputs for the seed, the seeding the xoshiro authors recommend, so a given seed gives the same stream as the reference C code. `seed_from_urand` reads 32 bytes of entropy straight into the state and replaces the one invalid state (all zero) with s0 = 1.

**Precision:** f32 uses top 24 bits of u64 (24-bit mantissa). f64 uses top 53 bits of u64 (53-bit mantissa). Both map to `[0, 1)` — 0.0 possible, 1.0 is not.

## Dependencies

```text
random/ depends on:
  → lib/urand/   (seeding only, via umath_random_xoshiro256_seed_from_urand;
                 optional — seed_from_u64 needs nothing)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

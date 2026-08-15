# random — umath Fast Pseudo-Random Number Generation

**Module:** `random/`
**Status:** Not yet swept — directory scaffolded, no files yet.
**Part of:** umath — unified math library

---

## Purpose

Fast, non-cryptographic PRNGs for numerical use: weight initialization,
dropout-style masking, Monte Carlo sampling, stochastic rounding. This is
explicitly *not* `lib/urand/`'s CSPRNG (per `PROJECTSTRUCTURE.md`,
hardware-entropy-seeded, security-sensitive) — a math-workload PRNG wants
speed and statistical quality over unpredictability, and reseeding from a
CSPRNG on every call would be wasted work for something like initializing
a large weight tensor.

## Planned scope

- A fast, well-distributed generator (xoshiro256++/PCG-shaped — algorithm
  choice deferred to when this folder is actually swept)
- Seeding from `lib/urand/` once, then running unseeded per-call
- Distribution samplers built on the raw generator: uniform, normal
  (Box-Muller or ziggurat), Bernoulli (for dropout masks)
- Array-fill variants (`random_fill_uniform_f32`, etc.) — the common case
  is filling a whole tensor, not drawing one scalar at a time

## Dependencies (anticipated)

```
random/ depends on:
  → lib/urand/  (seeding only, not per-call)
  → math_fn/    (log/sqrt for Box-Muller-style normal sampling)

random/ is depended on by:
  → whatever eventually does weight init / dropout / stochastic rounding
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

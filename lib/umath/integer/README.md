# integer — umath Integer Number Theory

**Module:** `integer/`
**Status:** Implemented — gcd/lcm/Bézout, exact roots and logs, modular arithmetic, deterministic primality, factorials and binomials (u64/i64)
**Part of:** umath — unified math library

---

## Purpose

Exact integer mathematics on 64-bit values: the building blocks for
hashing, cryptography helpers, rational arithmetic, combinatorics and
any code that needs `gcd`, `isqrt` or `a^b mod m` without going through
floating point. Every function returns the mathematically exact answer
for every input, or reports clearly that the answer does not fit in 64
bits.

## Files

```text
integer/
├── gcd.asm      ← gcd_u64 (binary/Stein), gcd_i64, lcm_u64 (+ _checked),
│                  egcd_i64 (Bézout coefficients)
├── root.asm     ← isqrt_u64, icbrt_u64, is_square_u64, ilog2_u64,
│                  ilog10_u64
├── modular.asm  ← mulmod_u64, powmod_u64, modinv_u64, ipow_u64
│                  (wrapping), ipow_u64_checked
├── prime.asm    ← is_prime_u64 (deterministic), next_prime_u64
└── combin.asm   ← factorial_u64, binomial_u64 (+ _checked)
```

## API

| Function | Args | Returns |
|---|---|---|
| `umath_gcd_u64` | `rdi` a, `rsi` b | `rax` gcd (gcd(0, 0) = 0) |
| `umath_gcd_i64` | `rdi` a, `rsi` b (signed) | `rax` gcd(\|a\|, \|b\|) as u64 |
| `umath_lcm_u64` | `rdi` a, `rsi` b | `rax` lcm, 0 if a or b is 0 or on overflow |
| `umath_lcm_u64_checked` | `rdi` a, `rsi` b, `rdx` u64 *out | `eax` 1 = fits (*out set), 0 = overflow |
| `umath_egcd_i64` | `rdi` a, `rsi` b, `rdx` i64 *x, `rcx` i64 *y | `rax` g with a·x + b·y = g |
| `umath_isqrt_u64` | `rdi` n | `rax` ⌊√n⌋ |
| `umath_icbrt_u64` | `rdi` n | `rax` ⌊∛n⌋ |
| `umath_is_square_u64` | `rdi` n | `eax` 1 if n is a perfect square |
| `umath_ilog2_u64` | `rdi` n | `eax` ⌊log2 n⌋, -1 for 0 |
| `umath_ilog10_u64` | `rdi` n | `eax` ⌊log10 n⌋, -1 for 0 |
| `umath_mulmod_u64` | `rdi` a, `rsi` b, `rdx` m | `rax` a·b mod m (0 for m = 0) |
| `umath_powmod_u64` | `rdi` b, `rsi` e, `rdx` m | `rax` b^e mod m (0 for m ≤ 1) |
| `umath_modinv_u64` | `rdi` a, `rsi` m | `rax` a⁻¹ mod m, 0 if none exists |
| `umath_ipow_u64` | `rdi` b, `rsi` e | `rax` b^e mod 2^64 |
| `umath_ipow_u64_checked` | `rdi` b, `rsi` e, `rdx` u64 *out | `eax` 1 = fits, 0 = overflow |
| `umath_is_prime_u64` | `rdi` n | `eax` 1 if prime |
| `umath_next_prime_u64` | `rdi` n | `rax` smallest prime > n, 0 if none fits |
| `umath_factorial_u64` | `rdi` n | `rax` n!, 0 for n > 20 |
| `umath_binomial_u64` | `rdi` n, `rsi` k | `rax` C(n, k), 0 on overflow or k > n |
| `umath_binomial_u64_checked` | `rdi` n, `rsi` k, `rdx` u64 *out | `eax` 1 = fits, 0 = overflow |

Output pointers may be NULL. A failed `_checked` call leaves `*out`
untouched.

## Design notes

**No division in gcd.** The binary algorithm removes the common power of
two once (`tzcnt`, with the SSE2-baseline fallback from `cpuid/`), then
only subtracts and shifts odd values.

**128-bit intermediates, never silent overflow.**
- `mulmod` reduces both factors, then divides the full 128-bit product
  by m. With both factors below m the quotient is too, so `div` cannot
  fault.
- `lcm`, `ipow_checked` and `binomial` detect overflow from the high
  half of the same 128-bit products. `binomial` checks before dividing:
  each step `C·(m+i)/i` is an exact binomial, and it fits exactly when
  the high half is below `i`.

**Exact roots from a float estimate.** `isqrt` starts from `sqrtsd` and
`icbrt` from `umath_cbrt_f64`. The estimate is then corrected by
comparing exact 128-bit squares/cubes with n. That makes them exact
above 2^53 too, where the double estimate is itself rounded.

**Primality is deterministic.**
- Trial division by the primes up to 37 settles small n and their
  multiples.
- Everything else goes through Miller–Rabin with those twelve primes as
  bases. That base set is proven exact for every n below 3.3·10²⁴, which
  covers all of u64; there is no probabilistic answer.

**Bézout without overflow.** `egcd_i64` runs on the magnitudes. Its
coefficients stay within max(\|a\|, \|b\|)/(2g) + 1, and the input
signs are applied at the end, so `INT64_MIN` is handled.

## Verification

`tests/test_integer.py` compares every function with Python's
arbitrary-precision integers (`math.gcd/lcm/isqrt/comb/factorial`,
three-argument `pow`, `pow(a, -1, m)`). It covers:
- random values of every bit length;
- boundary values (0, 1, 2^32 ± 1, 2^63, 2^64 − 1, perfect squares and
  cubes ± 1, powers of ten ± 1);
- for primality, every n below 100 000, Carmichael numbers, strong
  pseudoprimes to the small bases, and the largest 64-bit prime.

## Dependencies

```text
integer/ depends on:
  → cpuid/ (tzcnt fallback), math_fn/cbrt_f64.asm (icbrt's estimate)

integer/ is depended on by:
  → nothing yet (intended: hash/, rational arithmetic, crypto helpers)
```

---

*umath — unified math library*
*pure x86-64 assembly, no dependencies, no OS*

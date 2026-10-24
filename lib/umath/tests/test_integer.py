"""integer: gcd/lcm/egcd, isqrt/icbrt/ilog2/ilog10/is_square, mulmod/
powmod/modinv/ipow, is_prime/next_prime, factorial/binomial.

All exact, so every check compares with Python's arbitrary-precision
integers (math.gcd, math.isqrt, pow(b, e, m), pow(a, -1, m), math.comb ...)
over random values, boundary values (0, 1, 2^32 +- 1, 2^63, 2^64 - 1)
and known hard cases (Carmichael numbers, strong pseudoprimes to small
bases, the largest 64-bit prime).
"""
import ctypes as C
import math
import random

from umath_ref import I32, I64, P, U64, Checker, fn, load

lib = load()
ck = Checker('integer')
random.seed(41)
M64 = 2 ** 64 - 1
I64MIN = -2 ** 63


def u64s(n):
    edge = [0, 1, 2, 3, 2 ** 32 - 1, 2 ** 32, 2 ** 32 + 1, 2 ** 63 - 1, 2 ** 63, M64, M64 - 1, 10 ** 19,
            4294967291 ** 2, 2 ** 53 + 1, (2 ** 53 + 1) ** 2 % 2 ** 64]
    out = list(edge)
    for _ in range(n):
        bits = random.randint(1, 64)
        out.append(random.getrandbits(bits))
    return out


def run(name, cases, got_f, want_f):
    bad = []
    for c in cases:
        g, w = got_f(*c), want_f(*c)
        if g != w:
            bad.append((c, g, w))
    ck.check(name, not bad, bad[:1])


u = lambda name, n: fn(lib, f'umath_{name}', U64, *([U64] * n))

# --- gcd / lcm / egcd ------------------------------------------------------------
gcd = u('gcd_u64', 2)
vals = u64s(3000)
pairs = [(random.choice(vals), random.choice(vals)) for _ in range(6000)]
pairs += [(a * k, b * k) for a, b, k in ((random.getrandbits(20), random.getrandbits(20), random.getrandbits(20))
                                         for _ in range(1000))]
run('gcd_u64', pairs, gcd, math.gcd)
gcdi = fn(lib, 'umath_gcd_i64', U64, I64, I64)
spairs = [(random.choice(vals) - 2 ** 63 if random.random() < 0.5 else random.choice(vals) % 2 ** 63,
           -random.choice(vals) % 2 ** 63) for _ in range(3000)] + [(I64MIN, 0), (I64MIN, I64MIN), (0, I64MIN), (-6, 4)]
run('gcd_i64', spairs, gcdi, lambda a, b: math.gcd(a, b))
lcm = u('lcm_u64', 2)
run('lcm_u64 (0 on overflow)', pairs, lcm, lambda a, b: math.lcm(a, b) if math.lcm(a, b) <= M64 else 0)
lcmc = fn(lib, 'umath_lcm_u64_checked', I32, U64, U64, P)
out = C.c_uint64()
bad = []
for a, b in pairs[:3000]:
    out.value = 99
    ok = lcmc(a, b, C.addressof(out))
    w = math.lcm(a, b)
    if (w <= M64) != bool(ok) or (ok and out.value != w) or (not ok and out.value != 99):
        bad.append((a, b, ok, out.value, w))
ck.check('lcm_u64_checked', not bad, bad[:1])
egcd = fn(lib, 'umath_egcd_i64', U64, I64, I64, P, P)
x, y = C.c_int64(), C.c_int64()
bad = []
for a, b in spairs + [(0, 0), (5, 0), (0, -7), (240, 46), (-240, 46), (2 ** 62, 3)]:
    g = egcd(a, b, C.addressof(x), C.addressof(y))
    if g != math.gcd(a, b) or a * x.value + b * y.value != g or abs(x.value) > max(abs(a), abs(b), 1) \
            or abs(y.value) > max(abs(a), abs(b), 1):
        bad.append((a, b, g, x.value, y.value))
ck.check('egcd_i64 Bezout identity', not bad, bad[:1])

# --- roots and logs --------------------------------------------------------------
roots = vals + [k * k + d for k in (2 ** 32 - 1, 2 ** 31, 3037000499, 4294967295) for d in (-1, 0, 1)
                if 0 <= k * k + d <= M64]
roots += [k ** 3 + d for k in (2642245, 2097152, 1000000, 2642244) for d in (-1, 0, 1) if 0 <= k ** 3 + d <= M64]
roots += list(range(0, 2000))
run('isqrt_u64', [(v,) for v in roots], u('isqrt_u64', 1), math.isqrt)


def icbrt(n):
    r = round(n ** (1 / 3)) if n else 0
    while r ** 3 > n:
        r -= 1
    while (r + 1) ** 3 <= n:
        r += 1
    return r


run('icbrt_u64', [(v,) for v in roots], u('icbrt_u64', 1), icbrt)
run('is_square_u64', [(v,) for v in roots], fn(lib, 'umath_is_square_u64', I32, U64),
    lambda n: int(math.isqrt(n) ** 2 == n))
run('ilog2_u64', [(v,) for v in roots], fn(lib, 'umath_ilog2_u64', I32, U64), lambda n: n.bit_length() - 1)
pow10s = [10 ** k + d for k in range(20) for d in (-1, 0, 1) if 0 <= 10 ** k + d <= M64]
run('ilog10_u64', [(v,) for v in roots + pow10s], fn(lib, 'umath_ilog10_u64', I32, U64),
    lambda n: len(str(n)) - 1 if n else -1)

# --- modular arithmetic -----------------------------------------------------------
trip = [(random.choice(vals), random.choice(vals), random.choice(vals)) for _ in range(6000)]
run('mulmod_u64', trip, u('mulmod_u64', 3), lambda a, b, m: a * b % m if m else 0)
run('powmod_u64', trip[:3000] + [(0, 0, 7), (5, 0, 1), (2, 64, M64), (M64, M64, M64 - 1)], u('powmod_u64', 3),
    lambda b, e, m: pow(b, e, m) if m > 1 else 0)


def modinv(a, m):
    if m <= 1:
        return 0
    try:
        return pow(a, -1, m)
    except ValueError:
        return 0


run('modinv_u64', [(a, m) for a, _, m in trip] + [(3, 7), (0, 5), (2 ** 64 - 2, M64), (6, 9)],
    u('modinv_u64', 2), modinv)
run('ipow_u64 (wrapping)', [(random.choice(vals), random.randint(0, 200)) for _ in range(3000)],
    u('ipow_u64', 2), lambda b, e: pow(b, e, 2 ** 64))
ipc = fn(lib, 'umath_ipow_u64_checked', I32, U64, U64, P)
bad = []
cases = [(random.randint(0, 70000), random.randint(0, 70)) for _ in range(5000)]
cases += [(2, 63), (2, 64), (3, 40), (3, 41), (0, 0), (0, 100), (1, 10 ** 18), (M64, 1), (M64, 2), (2 ** 32, 2),
          (2 ** 32 - 1, 2), (10, 19), (10, 20)]
for b, e in cases:
    out.value = 7
    ok = ipc(b, e, C.addressof(out))
    w = b ** e
    if (w <= M64) != bool(ok) or (ok and out.value != w):
        bad.append((b, e, ok, out.value))
ck.check('ipow_u64_checked', not bad, bad[:1])

# --- primes -------------------------------------------------------------------
isp = fn(lib, 'umath_is_prime_u64', I32, U64)


def isprime(n):
    if n < 2:
        return 0
    for p in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if n % p == 0:
            return int(n == p)
    d, s = n - 1, 0
    while d % 2 == 0:
        d, s = d // 2, s + 1
    for a in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(s - 1):
            x = x * x % n
            if x == n - 1:
                break
        else:
            return 0
    return 1


sieve = bytearray([1]) * 100000
sieve[0] = sieve[1] = 0
for i in range(2, 317):
    if sieve[i]:
        sieve[i * i::i] = bytearray(len(sieve[i * i::i]))
ck.check('is_prime_u64 below 100000', all(isp(n) == sieve[n] for n in range(100000)))
hard = [561, 1105, 1729, 2465, 2821, 6601, 8911, 25326001, 3215031751, 2152302898747, 3474749660383,
        341550071728321, 3825123056546413051, 318665857834031151167461 % 2 ** 64, 18446744073709551557,
        18446744073709551559, 4294967291 * 4294967279, 2 ** 61 - 1, 2 ** 64 - 59, M64]
run('is_prime_u64 hard cases', [(n,) for n in hard], isp, isprime)
run('is_prime_u64 random', [(v | 1,) for v in vals], isp, isprime)
nxt = u('next_prime_u64', 1)


def next_prime(n):
    c = n + 1
    while c <= M64:
        if isprime(c):
            return c
        c += 1
    return 0


run('next_prime_u64', [(v,) for v in vals[:400]] + [(0,), (1,), (2,), (13,), (18446744073709551556,),
                                                    (18446744073709551557,), (M64,)], nxt, next_prime)

# --- combinatorics -------------------------------------------------------------
run('factorial_u64', [(n,) for n in range(30)], u('factorial_u64', 1),
    lambda n: math.factorial(n) if n <= 20 else 0)
bc = fn(lib, 'umath_binomial_u64_checked', I32, U64, U64, P)
bad = []
bcases = [(n, k) for n in range(0, 70) for k in range(0, 72)]
bcases += [(random.randint(0, 2 ** 64 - 1), random.randint(0, 3)) for _ in range(500)]
bcases += [(random.randint(60, 2000), random.randint(0, 40)) for _ in range(2000)] + [(67, 33), (68, 34), (M64, 1)]
for n, k in bcases:
    out.value = 5
    ok = bc(n, k, C.addressof(out))
    w = math.comb(n, k)
    if (w <= M64) != bool(ok) or (ok and out.value != w):
        bad.append((n, k, ok, out.value, w))
ck.check('binomial_u64_checked', not bad, bad[:1])
run('binomial_u64 (0 on overflow)', bcases[:3000], u('binomial_u64', 2),
    lambda n, k: math.comb(n, k) if math.comb(n, k) <= M64 else 0)

ck.finish()

"""reduce: sum/mean, dot/sum of squares, overflow-safe product, exact integer sums."""
import ctypes as C
import math
import random
from fractions import Fraction

from umath_ref import D, F, I64, P, U64, Z, Checker, fn, load, r32, same, ulp_diff

lib = load()
ck = Checker('reduce')
random.seed(13)
EPS64, EPS32 = 2.0 ** -53, 2.0 ** -24
inf, nan = math.inf, math.nan


def arr(t, vals):
    return (t * max(len(vals), 1))(*vals)


def round_frac(x, f32=False):
    v = float(x)                       # Fraction -> correctly rounded double
    return r32(v) if f32 else v


SIZES = [0, 1, 2, 3, 7, 8, 15, 16, 17, 255, 256, 257, 1000, 4099, 70000]

# --- sum: same algorithm as stability's pairwise sum; mean: compensated
for sfx, t, f32 in (('f64', D, False), ('f32', F, True)):
    s = fn(lib, f'umath_reduce_sum_{sfx}', t, P, Z)
    pw = fn(lib, f'umath_pairwise_sum_{sfx}', t, P, Z)
    mean = fn(lib, f'umath_reduce_mean_{sfx}', t, P, Z)
    rnd = r32 if f32 else float
    for n in SIZES:
        vals = [rnd(random.uniform(-100, 100)) for _ in range(n)]
        a = arr(t, vals)
        ck.check(f'reduce_sum_{sfx} is the pairwise sum', same(s(a, n), pw(a, n)), n)
        if n:
            want = round_frac(sum(Fraction(v) for v in vals) / n, f32)
            ck.check(f'reduce_mean_{sfx} within 1-2 ULP of exact', ulp_diff(mean(a, n), want, f32) <= (1 if f32 else 2), n)
    ck.check(f'reduce_mean_{sfx} empty is NaN', math.isnan(mean(None, 0)) and math.isnan(mean(arr(t, [1.0]), 0)))
    offset = [rnd(1e8 + random.uniform(-1, 1)) for _ in range(10001)]
    want = round_frac(sum(Fraction(v) for v in offset) / len(offset), f32)
    ck.check(f'reduce_mean_{sfx} large offset', ulp_diff(mean(arr(t, offset), len(offset)), want, f32) <= (1 if f32 else 2))

# --- dot / sumsq: error <= (lane terms + log2 n + 1) * eps * sum|a*b|
for sfx, t, f32, lanes in (('f64', D, False, 32), ('f32', F, True, 16)):
    dot = fn(lib, f'umath_reduce_dot_{sfx}', t, P, P, Z)
    ssq = fn(lib, f'umath_reduce_sumsq_{sfx}', t, P, Z)
    rnd = r32 if f32 else float
    eps = EPS32 if f32 else EPS64
    for n in SIZES:
        a = [rnd(random.uniform(-10, 10)) for _ in range(n)]
        b = [rnd(random.uniform(-10, 10)) for _ in range(n)]
        exact = sum(Fraction(x) * Fraction(y) for x, y in zip(a, b))
        mag = sum(abs(Fraction(x) * Fraction(y)) for x, y in zip(a, b))
        bound = (lanes + 2 + math.log2(max(n, 1))) * eps * float(mag)
        got = dot(arr(t, a), arr(t, b), n)
        ck.check(f'reduce_dot_{sfx} error bound', abs(Fraction(got) - exact) <= Fraction(bound), f'n={n}')
        exact_sq = sum(Fraction(x) ** 2 for x in a)
        got = ssq(arr(t, a), n)
        ck.check(f'reduce_sumsq_{sfx} error bound',
                 abs(Fraction(got) - exact_sq) <= Fraction((lanes + 2 + math.log2(max(n, 1))) * eps * float(exact_sq)), f'n={n}')
    for a, b, want in (([1.0, inf], [1.0, 1.0], inf), ([0.0], [inf], nan), ([1.0, nan], [1.0, 1.0], nan)):
        ck.check(f'reduce_dot_{sfx} non-finite', same(dot(arr(t, a), arr(t, b), len(a)), want), (a, b))
    ck.check(f'reduce_dot_{sfx} empty', dot(None, None, 0) == 0.0)

# --- product: relative error <= (n + 2) * eps of the exact product, and no
#     intermediate overflow/underflow
for sfx, t, f32 in (('f64', D, False), ('f32', F, True)):
    prod = fn(lib, f'umath_reduce_prod_{sfx}', t, P, Z)
    rnd = r32 if f32 else float
    eps = EPS32 if f32 else EPS64
    for n in (1, 2, 3, 10, 100, 1000):
        # 2^U(-1, 1) factors: log2 of the product drifts only ~sqrt(n), so the
        # true product stays in range (out-of-range draws are skipped)
        vals = [rnd(random.choice([1, -1]) * 2.0 ** random.uniform(-1, 1)) for _ in range(n)]
        exact = math.prod(Fraction(v) for v in vals)
        if math.isinf(round_frac(exact, f32)) or round_frac(exact, f32) == 0:
            continue
        got = prod(arr(t, vals), n)
        ck.check(f'reduce_prod_{sfx} accuracy', abs(Fraction(got) - exact) <= Fraction((n + 2) * EPS64) * abs(exact) + Fraction(eps) * abs(exact), f'n={n}')
    big = 1e200 if not f32 else 1e30
    cases = [
        ([big, big, 1 / big, 1 / big], 1.0),
        ([big] * 5 + [1 / big] * 5, 1.0),
        ([1 / big] * 3 + [big] * 3 + [2.0], 2.0),
        ([2.0 ** 600, 2.0 ** 600, 2.0 ** -1100], 2.0 ** 100) if not f32 else ([2.0 ** 100, 2.0 ** 100, 2.0 ** -190], 2.0 ** 10),
        ([5e-324, 2.0 ** 1000, 2.0 ** 74], 1.0) if not f32 else ([1e-45, 2.0 ** 100, 2.0 ** 49], r32(1e-45) * 2.0 ** 149),
    ]
    for vals, want in cases:
        vals = [rnd(v) for v in vals]
        exact = math.prod(Fraction(v) for v in vals)
        ck.check(f'reduce_prod_{sfx} no intermediate overflow', ulp_diff(prod(arr(t, vals), len(vals)), round_frac(exact, f32), f32) <= 2,
                 (vals, prod(arr(t, vals), len(vals))))
    top = 1e300 if not f32 else 1e30
    for vals, want in (([top, top], inf), ([-top, top], -inf), ([1 / top, 1 / top], 0.0), ([-1 / top, 1 / top], -0.0),
                       ([0.0, inf], nan), ([-1.0, 0.0], -0.0), ([-2.0, inf], -inf), ([nan, 1.0], nan), ([1.0, 2.0, nan], nan),
                       ([-0.0, -0.0], 0.0), ([], 1.0)):
        vals = [rnd(v) for v in vals]
        got = prod(arr(t, vals) if vals else None, len(vals))
        ck.check(f'reduce_prod_{sfx} special values', same(got, want), (vals, got))
    # gradual underflow: within one subnormal ULP of the correctly rounded
    # product (the rounded mantissa product is rounded again when scaled)
    if not f32:
        for _ in range(200):
            vals = [2.0 ** random.uniform(-600, -500), 2.0 ** random.uniform(-600, -500)]
            want = round_frac(Fraction(vals[0]) * Fraction(vals[1]))
            ck.check('reduce_prod_f64 subnormal result', ulp_diff(prod(arr(t, vals), 2), want) <= 1, vals)


# --- exact integer sums
class I128(C.Structure):
    _fields_ = [('lo', C.c_uint64), ('hi', C.c_uint64)]


s32 = fn(lib, 'umath_reduce_sum_i32', I64, P, Z)
u32 = fn(lib, 'umath_reduce_sum_u32', U64, P, Z)
s64 = fn(lib, 'umath_reduce_sum_i64', I128, P, Z)
u64 = fn(lib, 'umath_reduce_sum_u64', I128, P, Z)
for n in SIZES:
    v = [random.choice([-2 ** 31, 2 ** 31 - 1, random.randint(-2 ** 31, 2 ** 31 - 1)]) for _ in range(n)]
    ck.check('reduce_sum_i32 exact', s32((C.c_int32 * max(n, 1))(*v), n) == sum(v), n)
    v = [random.choice([0, 2 ** 32 - 1, random.randrange(2 ** 32)]) for _ in range(n)]
    ck.check('reduce_sum_u32 exact', u32((C.c_uint32 * max(n, 1))(*v), n) == sum(v), n)
    v = [random.choice([-2 ** 63, 2 ** 63 - 1, random.randint(-2 ** 63, 2 ** 63 - 1)]) for _ in range(n)]
    r = s64((C.c_int64 * max(n, 1))(*v), n)
    got = r.lo | r.hi << 64
    got = got - (1 << 128) if got >> 127 else got
    ck.check('reduce_sum_i64 exact (128-bit)', got == sum(v), n)
    v = [random.choice([0, 2 ** 64 - 1, random.randrange(2 ** 64)]) for _ in range(n)]
    r = u64((C.c_uint64 * max(n, 1))(*v), n)
    ck.check('reduce_sum_u64 exact (128-bit)', (r.lo | r.hi << 64) == sum(v), n)

ck.finish()

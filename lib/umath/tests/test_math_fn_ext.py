"""math_fn (extended): exp2/exp10/expm1, log2/log10/log1p, cbrt, scalbn,
atan/atan2/asin/acos, sinh/cosh/tanh, asinh/acosh/atanh.

Each function is swept over its domain (uniform regions plus log-uniform
magnitudes, edges included) against Python's math module and must stay
within a ULP bound: the measured worst case plus headroom (UMATH_VERBOSE=1
prints the measured worst per function). Special values, the documented
exactness promises and array/inplace == scalar (bit for bit) are checked
separately.
"""
import ctypes as C
import math
import os
import random
import struct
from fractions import Fraction

from umath_ref import D, F, I64, P, Z, Checker, fn, load, r32, same, ulp_diff

lib = load()
ck = Checker('math_fn_ext')
random.seed(23)
inf, nan = math.inf, math.nan
VERBOSE = os.environ.get('UMATH_VERBOSE') == '1'


def exp10_ref(x):
    try:
        return 10.0 ** x
    except OverflowError:
        return inf


def ovf(f, odd=False):
    def g(x):
        try:
            return f(x)
        except OverflowError:
            return math.copysign(inf, x) if odd else inf
        except ValueError:      # math raises where IEEE gives a value
            if x == 0 and f in (math.log2, math.log10):
                return -inf
            if abs(x) == 1 and f is math.atanh:
                return math.copysign(inf, x)
            return nan
    return g


def cbrt_ref(x):
    """Correctly rounded cube root (math.cbrt itself can be 3 ULP off):
    the neighbour of math.cbrt(x) whose exact cube is closest to x."""
    if x == 0 or not math.isfinite(x):
        return math.cbrt(x)
    y = math.cbrt(x)
    cands = [y]
    for _ in range(4):
        cands = [math.nextafter(cands[0], -inf)] + cands + [math.nextafter(cands[-1], inf)]
    fx = Fraction(x)
    return min(cands, key=lambda c: abs(Fraction(c) ** 3 - fx))


def logu(lo, hi, n, sign=1):
    return [sign * 10.0 ** random.uniform(lo, hi) for _ in range(n)]


def uni(lo, hi, n):
    return [random.uniform(lo, hi) for _ in range(n)]


# name: (reference, f64 bound, f32 bound, input generator)
FUNCS = {
    'exp2': (ovf(math.exp2), 2, 1, lambda: uni(-1080, 1030, 3000) + uni(-2, 2, 2000) + logu(-300, -1, 500, 1)
             + logu(-300, -1, 500, -1) + [float(k) for k in range(-1080, 1030, 7)]),
    'exp10': (exp10_ref, 2, 1, lambda: uni(-330, 312, 3000) + uni(-1, 1, 2000) + logu(-300, -1, 500, 1)
              + logu(-300, -1, 500, -1)),
    'expm1': (ovf(math.expm1), 3, 1, lambda: uni(-40, 710, 2000) + uni(-1, 1, 2000) + logu(-310, 0, 1000, 1)
              + logu(-310, 0, 1000, -1) + uni(-745, -30, 300)),
    'log2': (ovf(math.log2), 2, 1, lambda: logu(-323, 308, 3000) + uni(0.5, 2, 2000) + uni(0.999, 1.001, 500)),
    'log10': (ovf(math.log10), 3, 1, lambda: logu(-323, 308, 3000) + uni(0.5, 2, 2000) + uni(0.999, 1.001, 500)),
    'log1p': (ovf(math.log1p), 3, 1, lambda: logu(-310, 308, 2000) + logu(-310, -0.0001, 1000, -1)
              + uni(-0.999999, 1, 2000)),
    'cbrt': (cbrt_ref, 1, 1, lambda: logu(-323, 308, 3000, 1) + logu(-323, 308, 2000, -1) + uni(-10, 10, 1000)),
    'atan': (math.atan, 2, 1, lambda: logu(-310, 308, 2000) + logu(-310, 308, 2000, -1) + uni(-5, 5, 3000)),
    'asin': (ovf(math.asin), 3, 1, lambda: uni(-1, 1, 3000) + logu(-310, 0, 1000) + [1 - v for v in logu(-16, -1, 1000)]
             + [v - 1 for v in logu(-16, -1, 500)]),
    'acos': (ovf(math.acos), 2, 1, lambda: uni(-1, 1, 3000) + logu(-310, 0, 1000) + [1 - v for v in logu(-16, -1, 1000)]
             + [v - 1 for v in logu(-16, -1, 1000)]),
    'sinh': (ovf(math.sinh, odd=True), 3, 1, lambda: uni(-712, 712, 2000) + uni(-3, 3, 2000) + logu(-310, 0, 1000)
             + logu(-310, 0, 500, -1)),
    'cosh': (ovf(math.cosh), 2, 1, lambda: uni(-712, 712, 2000) + uni(-3, 3, 2000) + logu(-310, 0, 1000)),
    'tanh': (math.tanh, 3, 1, lambda: uni(-25, 25, 2000) + uni(-1, 1, 2000) + logu(-310, 0, 1000) + logu(-310, 0, 500, -1)),
    'asinh': (math.asinh, 3, 1, lambda: logu(-310, 308, 2000) + logu(-310, 308, 1000, -1) + uni(-3, 3, 2000)),
    'acosh': (ovf(math.acosh), 3, 1, lambda: [1 + v for v in logu(-16, 0, 1500)] + logu(0, 308, 1500) + uni(1, 3, 2000)),
    'atanh': (ovf(math.atanh), 3, 1, lambda: uni(-1, 1, 3000) + logu(-310, 0, 1000) + [1 - v for v in logu(-16, -1, 1000)]),
}

SPECIAL = {
    'exp2': [(0.0, 1.0), (-0.0, 1.0), (1.0, 2.0), (-1.0, 0.5), (1024.0, inf), (-1075.0, 0.0), (-1074.0, 5e-324),
             (inf, inf), (-inf, 0.0), (nan, nan)],
    'exp10': [(0.0, 1.0), (-0.0, 1.0), (309.0, inf), (-324.0, 0.0), (inf, inf), (-inf, 0.0), (nan, nan)],
    'expm1': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (-1e-300, -1e-300), (710.0, inf), (-40.0, -1.0),
              (inf, inf), (-inf, -1.0), (nan, nan)],
    'log2': [(1.0, 0.0), (0.0, -inf), (-0.0, -inf), (-1.0, nan), (inf, inf), (-inf, nan), (nan, nan)],
    'log10': [(1.0, 0.0), (0.0, -inf), (-0.0, -inf), (-1.0, nan), (inf, inf), (-inf, nan), (nan, nan)],
    'log1p': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (-1.0, -inf), (-2.0, nan), (inf, inf), (-inf, nan),
              (nan, nan)],
    'cbrt': [(0.0, 0.0), (-0.0, -0.0), (27.0, 3.0), (-8.0, -2.0), (inf, inf), (-inf, -inf), (nan, nan)],
    'atan': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (inf, math.pi / 2), (-inf, -math.pi / 2), (1.0, math.pi / 4),
             (nan, nan)],
    'asin': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (1.0, math.pi / 2), (-1.0, -math.pi / 2), (1.5, nan),
             (-1.5, nan), (inf, nan), (nan, nan)],
    'acos': [(1.0, 0.0), (-1.0, math.pi), (0.0, math.pi / 2), (-0.0, math.pi / 2), (1.5, nan), (-inf, nan), (nan, nan)],
    'sinh': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (711.0, inf), (-711.0, -inf), (inf, inf), (-inf, -inf),
             (nan, nan)],
    'cosh': [(0.0, 1.0), (-0.0, 1.0), (711.0, inf), (-711.0, inf), (inf, inf), (-inf, inf), (nan, nan)],
    'tanh': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (30.0, 1.0), (-30.0, -1.0), (inf, 1.0), (-inf, -1.0),
             (nan, nan)],
    'asinh': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (inf, inf), (-inf, -inf), (nan, nan)],
    'acosh': [(1.0, 0.0), (0.5, nan), (-1.0, nan), (inf, inf), (-inf, nan), (nan, nan)],
    'atanh': [(0.0, 0.0), (-0.0, -0.0), (1e-300, 1e-300), (1.0, inf), (-1.0, -inf), (1.5, nan), (inf, nan),
              (nan, nan)],
}

for name, (ref, b64, b32, gen) in FUNCS.items():
    for sfx, t, f32, bound in (('_f64', D, False, b64), ('_f32', F, True, b32)):
        f = fn(lib, f'umath_{name}{sfx}', t, t)
        arr = fn(lib, f'umath_{name}{sfx}_array', None, P, P, Z)
        inp = fn(lib, f'umath_{name}{sfx}_inplace', None, P, Z)
        xs = gen()
        if f32:
            xs = [r32(x) for x in xs]
        worst, at = 0, None
        for x in xs:
            u = ulp_diff(f(x), ref(x), f32)
            if u > worst:
                worst, at = u, x
        if VERBOSE:
            print(f'    {name}{sfx}: worst {worst} ULP at {at!r}')
        ck.check(f'{name}{sfx} within {bound} ULP', worst <= bound, f'{worst} ULP at {at!r}')
        for x, want in SPECIAL[name]:
            got = f(x)
            ck.check(f'{name}{sfx} special values', same(got, want if not f32 else r32(want)),
                     f'{name}({x!r}) = {got!r}, want {want!r}')
        # arrays and inplace: bit for bit what the scalar returns
        ct = C.c_float if f32 else C.c_double
        fmt = '<f' if f32 else '<d'
        for n in (0, 1, 2, 3, 7, 64):
            vals = [random.choice(xs + [s for s, _ in SPECIAL[name]]) for _ in range(n)]
            src = (ct * max(n, 1))(*vals)
            dst = (ct * max(n, 1))()
            arr(C.addressof(dst), C.addressof(src), n)
            buf = (ct * max(n, 1))(*vals)
            inp(C.addressof(buf), n)
            want = [struct.pack(fmt, f(v)) for v in vals]
            ck.check(f'{name}{sfx}_array matches the scalar', [struct.pack(fmt, v) for v in dst[:n]] == want, f'n={n}')
            ck.check(f'{name}{sfx}_inplace matches the scalar', [struct.pack(fmt, v) for v in buf[:n]] == want, f'n={n}')

# atan2(y, x): sweep, the IEEE special-value table, arrays bit for bit
pi = math.pi
for sfx, t, f32, bound in (('_f64', D, False, 3), ('_f32', F, True, 1)):
    f = fn(lib, f'umath_atan2{sfx}', t, t, t)
    arr = fn(lib, f'umath_atan2{sfx}_array', None, P, P, P, Z)
    mags = logu(-310, 308, 3000) + uni(0, 10, 2000)
    pairs = [(random.choice([1, -1]) * random.choice(mags), random.choice([1, -1]) * random.choice(mags))
             for _ in range(6000)]
    pairs += [(random.uniform(-1, 1), random.uniform(-1, 1)) for _ in range(3000)]
    if f32:
        pairs = [(r32(y), r32(x)) for y, x in pairs]
    worst, at = 0, None
    for y, x in pairs:
        u = ulp_diff(f(y, x), math.atan2(y, x), f32)
        if u > worst:
            worst, at = u, (y, x)
    if VERBOSE:
        print(f'    atan2{sfx}: worst {worst} ULP at {at!r}')
    ck.check(f'atan2{sfx} within {bound} ULP', worst <= bound, f'{worst} ULP at {at!r}')
    table = [((0.0, 1.0), 0.0), ((-0.0, 1.0), -0.0), ((0.0, 0.0), 0.0), ((-0.0, 0.0), -0.0),
             ((0.0, -0.0), pi), ((-0.0, -0.0), -pi), ((0.0, -1.0), pi), ((-0.0, -1.0), -pi),
             ((1.0, 0.0), pi / 2), ((-1.0, -0.0), -pi / 2), ((inf, inf), pi / 4), ((-inf, inf), -pi / 4),
             ((inf, -inf), 3 * pi / 4), ((-inf, -inf), -3 * pi / 4), ((inf, 5.0), pi / 2), ((-inf, -5.0), -pi / 2),
             ((5.0, inf), 0.0), ((-5.0, inf), -0.0), ((5.0, -inf), pi), ((-5.0, -inf), -pi),
             ((nan, 1.0), nan), ((1.0, nan), nan), ((1e300, 1e-300), pi / 2), ((1e-300, 1e300), 0.0)]
    for (y, x), want in table:
        got = f(y, x)
        ck.check(f'atan2{sfx} special values', same(got, r32(want) if f32 else want),
                 f'atan2({y!r}, {x!r}) = {got!r}, want {want!r}')
    ct = C.c_float if f32 else C.c_double
    fmt = '<f' if f32 else '<d'
    for n in (0, 1, 2, 5, 64):
        sel = [random.choice(pairs + [k for k, _ in table]) for _ in range(n)]
        ys = (ct * max(n, 1))(*[y for y, _ in sel])
        xs = (ct * max(n, 1))(*[x for _, x in sel])
        dst = (ct * max(n, 1))()
        arr(C.addressof(dst), C.addressof(ys), C.addressof(xs), n)
        ck.check(f'atan2{sfx}_array matches the scalar',
                 [struct.pack(fmt, v) for v in dst[:n]] == [struct.pack(fmt, f(y, x)) for y, x in sel], f'n={n}')

# exactness promises
exp2 = fn(lib, 'umath_exp2_f64', D, D)
ck.check('exp2 of an integer is exact', all(exp2(float(k)) == math.ldexp(1.0, k) for k in range(-1074, 1024)))
exp10 = fn(lib, 'umath_exp10_f64', D, D)
ck.check('exp10(0..22) is exact', all(exp10(float(k)) == 10.0 ** k for k in range(23)))
log2 = fn(lib, 'umath_log2_f64', D, D)
ck.check('log2 of a power of two is exact', all(log2(math.ldexp(1.0, k)) == k for k in range(-1074, 1024)))
log10 = fn(lib, 'umath_log10_f64', D, D)
ck.check('log10(10^0..10^22) is exact', all(log10(10.0 ** k) == k for k in range(23)))
cbrt = fn(lib, 'umath_cbrt_f64', D, D)
ck.check('cbrt of a perfect cube is exact', all(cbrt(float(k) ** 3) == k for k in range(-2000, 2000)))

# scalbn / ldexp: exact, or one rounding into the subnormal range
for name in ('umath_scalbn_f64', 'umath_ldexp_f64'):
    sc = fn(lib, name, D, D, I64)
    bad = []
    for _ in range(4000):
        x = random.choice([1.0, -1.0, 0.75]) * 2.0 ** random.uniform(-1074, 1023)
        n = random.choice([random.randint(-2200, 2200), random.randint(-60, 60), 2 ** 40, -2 ** 40])
        try:
            want = math.ldexp(x, n)
        except OverflowError:
            want = math.copysign(inf, x)
        got = sc(x, n)
        if not same(got, want):
            bad.append((x, n, got, want))
    for x in (0.0, -0.0, inf, -inf, nan):
        if not same(sc(x, 5), x):
            bad.append((x, 5, sc(x, 5), x))
    ck.check(f'{name} matches math.ldexp exactly', not bad, bad[:1])

ck.finish()

"""math_fn: sqrt/exp/log/pow/sin/cos/tan/hypot against Python's math module.

ULP bounds are the measured worst cases with a little headroom; pow's bound
grows with |y*ln(x)| because exp(y*ln(x)) amplifies log's rounding error.
"""
import math
import random

from umath_ref import D, F, P, Z, Checker, fn, load, r32, same, ulp_diff

lib = load()
ck = Checker('math_fn')
random.seed(1)
inf, nan = math.inf, math.nan


def ref(f):
    """libm semantics where Python raises: log(0) = -Inf, pow(0, -1) = Inf..."""
    def g(*a):
        try:
            return f(*a)
        except OverflowError:
            return math.inf
        except ValueError:
            if f is math.log and a[0] == 0:
                return -math.inf
            if f is math.pow and a[0] == 0:
                odd = float(a[1]).is_integer() and int(a[1]) % 2 == 1
                return math.copysign(math.inf, a[0]) if odd else math.inf
            return math.nan
    return g


def sweep(name, mf, lo, hi, bound, n=4000, log=False, two=None):
    for sfx, t, f32 in (('_f64', D, False), ('_f32', F, True)):
        f = fn(lib, f'umath_{name}{sfx}', t, *([t] * (2 if two else 1)))
        worst = (0, None)
        for _ in range(n):
            x = math.exp(random.uniform(math.log(lo), math.log(hi))) if log else random.uniform(lo, hi)
            args = (x, random.uniform(*two)) if two else (x,)
            if f32:
                args = tuple(r32(a) for a in args)
            u = ulp_diff(f(*args), ref(mf)(*args), f32)
            limit = bound(*args) if callable(bound) else bound
            if u > limit and u > worst[0]:
                worst = (u, args)
        ck.check(f'{name}{sfx} [{lo:g},{hi:g}] within bound', worst[1] is None,
                 f'{worst[0]} ULP at {worst[1]}')


sweep('sqrt', math.sqrt, 1e-300, 1e300, 0, log=True)
sweep('exp', math.exp, -745, 709, 2)
sweep('exp', math.exp, -20, 20, 2)
sweep('log', math.log, 1e-300, 1e300, 3, log=True)
sweep('log', math.log, 0.5, 2, 3)
sweep('sin', math.sin, -10, 10, 3)
sweep('sin', math.sin, -1e6, 1e6, 3)
sweep('cos', math.cos, -10, 10, 3)
sweep('cos', math.cos, -1e6, 1e6, 3)
sweep('tan', math.tan, -1.5, 1.5, 4)
sweep('hypot', math.hypot, -1e3, 1e3, 2, two=(-1e3, 1e3))
sweep('pow', math.pow, 0.01, 100, lambda x, y: 4 + 4 * abs(y * math.log(x)), two=(-20, 20))
sweep('pow', math.pow, 1.0001, 10, lambda x, y: 4 + 4 * abs(y * math.log(x)), two=(100, 300))

# sin/cos keep ~1 ULP of absolute accuracy up to the documented 2^32*pi/2
sin64, cos64 = fn(lib, 'umath_sin_f64', D, D), fn(lib, 'umath_cos_f64', D, D)
for _ in range(2000):
    x = random.uniform(-6.5e9, 6.5e9)
    ck.check('sin_f64 |x| <= 6.5e9 abs error', abs(sin64(x) - math.sin(x)) <= 2.3e-16, x)
    ck.check('cos_f64 |x| <= 6.5e9 abs error', abs(cos64(x) - math.cos(x)) <= 2.3e-16, x)

specials = {
    'exp': [nan, inf, -inf, 710.0, 1000.0, -745.0, -1000.0, -0.0, 0.0, 709.7, -740.0],
    'log': [nan, inf, -1.0, 0.0, -0.0, 5e-324, 1.0, -inf],
    'sqrt': [nan, inf, -1.0, -0.0, 0.0, 5e-324, -inf],
    'sin': [nan, inf, -inf, -0.0, 0.0, 1e-30, -1e-30],
    'cos': [nan, inf, -0.0],
    'tan': [nan, -0.0, 0.0],
    'hypot': [(inf, nan), (nan, inf), (1e300, 1e300), (1e-300, 1e-300), (3.0, 4.0), (-0.0, -0.0)],
    'pow': [(-0.0, -1.0), (-0.0, 3.0), (0.0, 3.0), (-0.0, 2.0), (-0.0, -2.0), (0.0, -inf), (-1.0, inf),
            (-1.0, -inf), (-1.0, 3.0), (2.0, inf), (0.5, inf), (2.0, -inf), (inf, 1.0), (inf, -1.0),
            (-inf, 3.0), (-inf, -3.0), (2.0, -1074.0), (nan, 0.0), (1.0, nan), (-8.0, 1 / 3), (-2.0, 3.0)],
}
for name, cases in specials.items():
    for sfx, t, f32 in (('_f64', D, False), ('_f32', F, True)):
        two = isinstance(cases[0], tuple)
        f = fn(lib, f'umath_{name}{sfx}', t, *([t] * (2 if two else 1)))
        for c in cases:
            args = c if two else (c,)
            if f32:
                args = tuple(r32(a) for a in args)
            want = ref(getattr(math, name))(*args)
            if f32:
                want = r32(want)
            got = f(*args)
            ok = same(got, want) or (want != 0 and not math.isinf(want) and ulp_diff(got, want, f32) <= 4)
            ck.check(f'{name}{sfx} special values', ok, f'{name}{sfx}{args} = {got!r}, want {want!r}')

# sin/cos beyond the reduction's domain: NaN rather than garbage
for name in ('sin', 'cos'):
    for sfx, t in (('_f64', D), ('_f32', F)):
        f = fn(lib, f'umath_{name}{sfx}', t, t)
        for x in (4503599627370496.0, -1e18, 1e30):
            ck.check(f'{name}{sfx} NaN at |x| >= 2^52', math.isnan(f(x)), x)

# array/inplace variants must match the scalar routine element for element
for name in ('exp', 'log', 'sqrt', 'sin', 'cos', 'tan'):
    for sfx, t in (('_f64', D), ('_f32', F)):
        scalar = fn(lib, f'umath_{name}{sfx}', t, t)
        arr = fn(lib, f'umath_{name}{sfx}_array', None, P, P, Z)
        inp = fn(lib, f'umath_{name}{sfx}_inplace', None, P, Z)
        for n in (0, 1, 3, 4, 5, 7, 8, 9, 17, 33):
            vals = [random.uniform(0.1, 5) for _ in range(n)] + []
            if n > 2:
                vals[1] = nan
                vals[2] = 1000.0
            src = (t * n)(*vals)
            dst = (t * n)()
            buf = (t * n)(*vals)
            arr(dst, src, n)
            inp(buf, n)
            want = [scalar(v) for v in vals]
            ok = all(same(a, b) for a, b in zip(dst, want)) and all(same(a, b) for a, b in zip(buf, want))
            ck.check(f'{name}{sfx} array/inplace == scalar', ok, f'n={n}')

ck.finish()

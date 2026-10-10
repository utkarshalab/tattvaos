"""scalar: rounding, abs/neg/sign, min/max/clamp, reductions."""
import math
import random

from umath_ref import D, F, I32, I64, P, Z, Checker, fn, load, r32, same

lib = load()
ck = Checker('scalar')
random.seed(3)
nan, inf = math.nan, math.inf


def keep_special(f):
    return lambda x: x if math.isinf(x) or math.isnan(x) else math.copysign(float(f(x)), x)


def rint(x):
    return x if math.isinf(x) or math.isnan(x) else math.copysign(float(round(x)), x)


def sgn(x):
    return x if math.isnan(x) or x == 0 else math.copysign(1.0, x)


unary = {
    'floor': keep_special(math.floor), 'ceil': keep_special(math.ceil), 'trunc': keep_special(math.trunc),
    'round': rint, 'neg': lambda x: -x, 'abs': abs, 'sign': sgn,
}
specials = [0.0, -0.0, 0.5, -0.5, 1.5, 2.5, -2.5, 0.49999999999999994, 1e300, -1e300,
            4503599627370497.0, 8388609.0, inf, -inf, nan, 5e-324, -5e-324, 1e-40]
for name, rf in unary.items():
    for sfx, t, f32 in (('_f64', D, False), ('_f32', F, True)):
        f = fn(lib, f'umath_{name}{sfx}', t, t)
        xs = specials + [random.uniform(-1e6, 1e6) for _ in range(2000)] + [random.uniform(-3, 3) for _ in range(2000)]
        for x in xs:
            if f32:
                x = r32(x)
            want = r32(rf(x)) if f32 else rf(x)
            ck.check(f'{name}{sfx}', same(f(x), want), f'{name}{sfx}({x!r}) = {f(x)!r}, want {want!r}')
        arr = fn(lib, f'umath_{name}{sfx}_array', None, P, P, Z)
        inp = fn(lib, f'umath_{name}{sfx}_inplace', None, P, Z)
        for n in (1, 2, 3, 4, 5, 7, 8, 9, 15, 16, 17, 33, 70):
            vals = [random.choice([random.uniform(-100, 100), -0.0, 0.0, nan, -inf]) for _ in range(n)]
            src, dst, b = (t * n)(*vals), (t * n)(), (t * n)(*vals)
            arr(dst, src, n)
            inp(b, n)
            want = [f(v) for v in src]
            ck.check(f'{name}{sfx}_array == scalar', all(same(a, w) for a, w in zip(dst, want)), f'n={n}')
            ck.check(f'{name}{sfx}_inplace == scalar', all(same(a, w) for a, w in zip(b, want)), f'n={n}')

for sfx, t in (('_f64', D), ('_f32', F)):
    isn, isi = fn(lib, f'umath_abs{sfx}_isnan', I32, t), fn(lib, f'umath_abs{sfx}_isinf', I32, t)
    cs = fn(lib, f'umath_abs{sfx}_copysign', t, t, t)
    for x in (0.0, -1.5, inf, -inf, nan):
        ck.check(f'abs{sfx}_isnan', isn(x) == int(math.isnan(x)), x)
        ck.check(f'abs{sfx}_isinf', isi(x) == int(math.isinf(x)), x)
        got = cs(x, -2.0)
        ck.check(f'abs{sfx}_copysign', math.isnan(got) if math.isnan(x) else same(got, -abs(x)), x)
    cneg = fn(lib, f'umath_abs{sfx}_count_negative', I64, P, Z)
    for n in (1, 5, 16, 37):
        vals = [random.uniform(-5, 5) for _ in range(n)]
        ck.check(f'abs{sfx}_count_negative', cneg((t * n)(*vals), n) == sum(v < 0 for v in vals), n)

for bits, t in ((32, I32), (64, I64)):
    lo, hi = -2 ** (bits - 1), 2 ** (bits - 1) - 1
    a, sat = fn(lib, f'umath_abs_i{bits}', t, t), fn(lib, f'umath_abs_i{bits}_sat', t, t)
    for x in (0, 1, -1, hi, lo, lo + 1, random.randint(lo, hi)):
        ck.check(f'abs_i{bits}', a(x) == (abs(x) if x != lo else lo), x)
        ck.check(f'abs_i{bits}_sat', sat(x) == min(abs(x), hi), x)
    arr, inp = fn(lib, f'umath_abs_i{bits}_array', None, P, P, Z), fn(lib, f'umath_abs_i{bits}_inplace', None, P, Z)
    for n in (1, 3, 4, 7, 16, 17, 40):
        vals = [random.randint(lo + 1, hi) for _ in range(n)]
        src, dst, b = (t * n)(*vals), (t * n)(), (t * n)(*vals)
        arr(dst, src, n)
        inp(b, n)
        ck.check(f'abs_i{bits}_array', list(dst) == [abs(v) for v in vals], n)
        ck.check(f'abs_i{bits}_inplace', list(b) == [abs(v) for v in vals], n)
    sarr = fn(lib, f'umath_abs_i{bits}_sat_array', None, P, P, Z)
    sinp = fn(lib, f'umath_abs_i{bits}_sat_inplace', None, P, Z)
    for n in (1, 3, 4, 7, 16, 17, 40):
        vals = [random.choice([lo, lo + 1, -1, 0, hi, random.randint(lo, hi)]) for _ in range(n)]
        src, dst, b = (t * n)(*vals), (t * n)(), (t * n)(*vals)
        sarr(dst, src, n)
        sinp(b, n)
        want = [min(abs(v), hi) for v in vals]
        ck.check(f'abs_i{bits}_sat_array', list(dst) == want, n)
        ck.check(f'abs_i{bits}_sat_inplace', list(b) == want, n)

for op, pf in (('min', min), ('max', max)):
    for sfx, t, f32 in (('_f64', D, False), ('_f32', F, True)):
        red = fn(lib, f'umath_{op}{sfx}_reduce', t, P, Z)
        rng = fn(lib, f'umath_{op}{sfx}_reduce_range', t, P, Z, Z)
        idx = fn(lib, f'umath_{op}{sfx}_reduce_index', I64, P, Z)
        for n in (1, 2, 3, 4, 5, 8, 9, 16, 17, 33, 100):
            vals = [random.uniform(-1e3, 1e3) for _ in range(n)]
            if f32:
                vals = [r32(v) for v in vals]
            arr = (t * n)(*vals)
            ck.check(f'{op}{sfx}_reduce', same(red(arr, n), pf(vals)), n)
            ck.check(f'{op}{sfx}_reduce_range', same(rng(arr, 0, n), pf(vals)), n)
            ck.check(f'{op}{sfx}_reduce_index', idx(arr, n) == vals.index(pf(vals)), n)
            for k in range(min(n, 4)):
                withnan = list(vals)
                withnan[k] = nan
                ck.check(f'{op}{sfx}_reduce propagates NaN', math.isnan(red((t * n)(*withnan), n)), f'n={n} nan at {k}')
                ck.check(f'{op}{sfx}_reduce_range propagates NaN', math.isnan(rng((t * n)(*withnan), 0, n)), f'n={n} nan at {k}')
        ieee = fn(lib, f'umath_{op}{sfx}_ieee', t, t, t)
        for a, b in ((1.0, 2.0), (2.0, 1.0), (-0.0, 0.0), (0.0, -0.0), (nan, 1.0), (1.0, nan), (-inf, 3.0)):
            if math.isnan(a) or math.isnan(b):
                want = b if math.isnan(a) else a           # IEEE 754-2008 minNum/maxNum
            elif a == b == 0:                              # -0 < +0 for min/max
                negs = [z for z in (a, b) if math.copysign(1, z) < 0]
                want = (-0.0 if negs else 0.0) if op == 'min' else (0.0 if len(negs) < 2 else -0.0)
            else:
                want = pf(a, b)
            ck.check(f'{op}{sfx}_ieee', same(ieee(a, b), want), (a, b))

for op, pf in (('min', min), ('max', max)):
    for bits, t in ((32, I32), (64, I64)):
        lo, hi = -2 ** (bits - 1), 2 ** (bits - 1) - 1
        f = fn(lib, f'umath_{op}_i{bits}', t, t, t)
        for a, b in ((lo, hi), (hi, lo), (-1, 1), (5, 5), (lo, -1)):
            ck.check(f'{op}_i{bits}', f(a, b) == pf(a, b), (a, b))
        red, idx = fn(lib, f'umath_{op}_i{bits}_reduce', t, P, Z), fn(lib, f'umath_{op}_i{bits}_reduce_index', I64, P, Z)
        for n in (1, 2, 3, 4, 5, 7, 8, 9, 16, 17, 33, 100):
            vals = [random.randint(lo, hi) for _ in range(n)]
            arr = (t * n)(*vals)
            ck.check(f'{op}_i{bits}_reduce', red(arr, n) == pf(vals), n)
            ck.check(f'{op}_i{bits}_reduce_index', idx(arr, n) == vals.index(pf(vals)), n)

for sfx, t in (('_f64', D), ('_f32', F)):
    f = fn(lib, f'umath_clamp{sfx}', t, t, t, t)
    for v, lo, hi in ((5.0, 0.0, 1.0), (-5.0, 0.0, 1.0), (0.5, 0.0, 1.0)):
        ck.check(f'clamp{sfx}', same(f(v, lo, hi), min(max(v, lo), hi)), v)
fc = fn(lib, 'umath_clamp_i32', I32, I32, I32, I32)
for v, lo, hi in ((5, 0, 1), (-5, 0, 1), (2 ** 31 - 1, -10, 10), (-2 ** 31, -10, 10)):
    ck.check('clamp_i32', fc(v, lo, hi) == min(max(v, lo), hi), v)

for name, rf in (('floor', math.floor), ('ceil', math.ceil), ('trunc', math.trunc), ('round', lambda x: int(round(x)))):
    f64, f32 = fn(lib, f'umath_{name}_f64_to_i64', I64, D), fn(lib, f'umath_{name}_f32_to_i32', I32, F)
    for x in (2.5, -2.5, 1.7, -1.7, 0.5, 1e10):
        ck.check(f'{name}_f64_to_i64', f64(x) == rf(x), x)
    for x in (2.5, -2.5, 1.7, -1.7, 0.5):
        ck.check(f'{name}_f32_to_i32', f32(x) == rf(x), x)

rcp = fn(lib, 'umath_reciprocal_f32', F, F)
for x in (3.0, -7.0, 0.0, -0.0, inf, nan, 1e-30):
    want = math.copysign(inf, x) if x == 0 else (nan if math.isnan(x) else r32(1 / x))
    ck.check('reciprocal_f32', same(rcp(r32(x)), want), x)

ck.finish()

"""IEEE 754 helpers: fmod/remainder/remquo, frexp/ilogb/logb/modf,
nextafter/nextup/nextdown, fdim, scalbn/ldexp (f32) and fma.

These operations are exact (or rounded exactly once), so every check is
bit for bit against an exact reference: Python's own fmod/remainder/
frexp/modf/nextafter/ldexp/fma, which are exact, or Fraction arithmetic.
Under UMATH_CPU_MASK=0 the fma checks exercise the integer software path
(no FMA3).
"""
import ctypes as C
import math
import random
import struct
from fractions import Fraction

from umath_ref import D, F, I32, I64, P, Z, Checker, fn, load, r32, same

lib = load()
ck = Checker('ieee')
random.seed(31)
inf, nan = math.inf, math.nan


def f32bits(x):
    return struct.unpack('<I', struct.pack('<f', x))[0]


def f32(b):
    return struct.unpack('<f', struct.pack('<I', b & 0xFFFFFFFF))[0]


def rnd32(q):
    """Fraction -> nearest float32, ties to even, overflow to Inf."""
    if q == 0:
        return 0.0
    s = -1.0 if q < 0 else 1.0
    q = abs(q)
    if q >= Fraction(2) ** 128 - Fraction(2) ** 103:
        return s * inf
    c = r32(float(q))
    best = None
    for b in (f32bits(c) - 1, f32bits(c), f32bits(c) + 1):
        if b < 0 or b >= 0x7F800000:
            continue
        v = f32(b)
        d = abs(Fraction(v) - q)
        if best is None or d < best[0] or (d == best[0] and b % 2 == 0):
            best = (d, b, v)
    return s * best[2]


def doubles(n):
    out = []
    for _ in range(n):
        r = random.random()
        if r < 0.15:
            out.append(random.choice([0.0, -0.0, inf, -inf, nan, 5e-324, -5e-324, 1.7976931348623157e308,
                                      2.2250738585072014e-308, 1.0, -1.0, 0.5, 3.0]))
        elif r < 0.5:
            out.append(random.uniform(-100, 100))
        else:
            out.append(random.choice([1, -1]) * 2.0 ** random.uniform(-1074, 1023))
    return out


def bits_same(a, b):
    return same(a, b)


# --- fmod / remainder / remquo -------------------------------------------------
for w, t, f32mode in (('f64', D, False), ('f32', F, True)):
    fm = fn(lib, f'umath_fmod_{w}', t, t, t)
    rem = fn(lib, f'umath_remainder_{w}', t, t, t)
    rq = fn(lib, f'umath_remquo_{w}', t, t, t, P)
    xs, ys = doubles(6000), doubles(6000)
    pairs = list(zip(xs, ys)) + [(random.uniform(-1e6, 1e6), random.uniform(-10, 10)) for _ in range(3000)]
    pairs += [(k * 0.5, 1.0) for k in range(-20, 21)] + [(k * 1.5, 3.0) for k in range(-20, 21)]
    if f32mode:
        pairs = [(r32(x), r32(y)) for x, y in pairs]
    bad = {'fmod': [], 'remainder': [], 'remquo': []}
    quo = C.c_int32()
    for x, y in pairs:
        try:
            want = math.fmod(x, y)
        except ValueError:
            want = nan
        if math.isnan(x) or math.isnan(y):
            want = nan
        if not same(fm(x, y), want):
            bad['fmod'].append((x, y, fm(x, y), want))
        try:
            want = math.remainder(x, y)
        except ValueError:
            want = nan
        if math.isnan(x) or math.isnan(y):
            want = nan
        if not same(rem(x, y), want):
            bad['remainder'].append((x, y, rem(x, y), want))
        quo.value = 12345
        got = rq(x, y, C.addressof(quo))
        if not same(got, want):
            bad['remquo'].append((x, y, got, want))
        elif math.isfinite(x) and math.isfinite(y) and y != 0 and x != 0:
            if math.isinf(y):
                qwant = 0
            else:
                n = (Fraction(x) - Fraction(want)) / Fraction(y)   # exact integer quotient
                qwant = (abs(int(n)) % 8) * (-1 if n < 0 else 1)
                if n == 0:
                    qwant = 0
            if quo.value != qwant and not (qwant == 0 and quo.value == 0):
                bad['remquo'].append((x, y, 'quo', quo.value, qwant))
    for k, v in bad.items():
        ck.check(f'{k}_{w} is exact', not v, v[:1])
    # arrays
    for name in ('fmod', 'remainder'):
        arr = fn(lib, f'umath_{name}_{w}_array', None, P, P, P, Z)
        ct = C.c_float if f32mode else C.c_double
        sel = random.sample(pairs, 50)
        a = (ct * 50)(*[x for x, _ in sel])
        b = (ct * 50)(*[y for _, y in sel])
        d = (ct * 50)()
        arr(C.addressof(d), C.addressof(a), C.addressof(b), 50)
        scalar = fm if name == 'fmod' else rem
        ck.check(f'{name}_{w}_array matches the scalar', all(same(d[i], scalar(a[i], b[i])) for i in range(50)))
    ck.check(f'remquo_{w} accepts a NULL quo', same(rq(7.0, 2.0, None), -1.0))

# --- frexp / ilogb / logb / modf ---------------------------------------------
for w, t, f32mode in (('f64', D, False), ('f32', F, True)):
    frexp = fn(lib, f'umath_frexp_{w}', t, t, P)
    ilogb = fn(lib, f'umath_ilogb_{w}', I32, t)
    logb = fn(lib, f'umath_logb_{w}', t, t)
    modf = fn(lib, f'umath_modf_{w}', t, t, P)
    xs = doubles(8000) + [float(k) + 0.25 for k in range(-50, 50)]
    if f32mode:
        xs = [r32(x) for x in xs] + [r32(v) for v in (1.4e-45, -1.4e-45, 1.1754942e-38)]
    e = C.c_int32()
    ip = (C.c_float if f32mode else C.c_double)()
    bad = {'frexp': [], 'ilogb': [], 'logb': [], 'modf': []}
    for x in xs:
        e.value = 777
        m = frexp(x, C.addressof(e))
        if math.isfinite(x):
            wm, we = math.frexp(x)
        else:
            wm, we = x, 0
        if not same(m, wm) or e.value != we:
            bad['frexp'].append((x, m, e.value, wm, we))
        if x == 0 or math.isnan(x):
            wi = -2 ** 31
        elif math.isinf(x):
            wi = 2 ** 31 - 1
        else:
            wi = math.frexp(x)[1] - 1
        if ilogb(x) != wi:
            bad['ilogb'].append((x, ilogb(x), wi))
        if x == 0:
            wl = -inf
        elif math.isinf(x):
            wl = inf
        elif math.isnan(x):
            wl = nan
        else:
            wl = float(math.frexp(x)[1] - 1)
        if not same(logb(x), wl):
            bad['logb'].append((x, logb(x), wl))
        frac = modf(x, C.addressof(ip))
        if math.isnan(x):
            ok = math.isnan(frac) and math.isnan(ip.value)
        else:
            wf, wint = math.modf(x)
            ok = same(frac, wf) and same(ip.value, wint)
        if not ok:
            bad['modf'].append((x, frac, ip.value, math.modf(x) if not math.isnan(x) else None))
    for k, v in bad.items():
        ck.check(f'{k}_{w} is exact', not v, v[:1])
    ck.check(f'frexp/modf_{w} accept NULL', same(frexp(3.0, None), 0.75) and same(modf(2.5, None), 0.5))

# --- nextafter / nextup / nextdown / fdim -------------------------------------
for w, t, f32mode in (('f64', D, False), ('f32', F, True)):
    na = fn(lib, f'umath_nextafter_{w}', t, t, t)
    up = fn(lib, f'umath_nextup_{w}', t, t)
    dn = fn(lib, f'umath_nextdown_{w}', t, t)
    fd = fn(lib, f'umath_fdim_{w}', t, t, t)
    xs, ys = doubles(6000), doubles(6000)
    if f32mode:
        xs, ys = [r32(x) for x in xs], [r32(y) for y in ys]

    def nxt(x, y):
        if not f32mode:
            return math.nextafter(x, y)
        if math.isnan(x) or math.isnan(y):
            return nan
        if x == y:
            return y
        if x == 0:
            return math.copysign(f32(1), y)
        b = f32bits(x)
        return f32(b + 1) if (x < y) == (x > 0) else f32(b - 1)

    bad = {'nextafter': [], 'nextup': [], 'nextdown': [], 'fdim': []}
    for x, y in zip(xs, ys):
        if not same(na(x, y), nxt(x, y)):
            bad['nextafter'].append((x, y, na(x, y), nxt(x, y)))
        if not same(up(x), nxt(x, inf)):
            bad['nextup'].append((x, up(x), nxt(x, inf)))
        if not same(dn(x), nxt(x, -inf)):
            bad['nextdown'].append((x, dn(x), nxt(x, -inf)))
        if math.isnan(x) or math.isnan(y):
            wd = nan
        elif x > y:
            wd = (r32(x - y) if f32mode else x - y)
        else:
            wd = 0.0
        if not same(fd(x, y), wd):
            bad['fdim'].append((x, y, fd(x, y), wd))
    for k, v in bad.items():
        ck.check(f'{k}_{w} is exact', not v, v[:1])
    ck.check(f'nextafter_{w}(+0, -0) is -0', same(na(0.0, -0.0), -0.0))

# --- scalbn / ldexp for floats -----------------------------------------------
for name in ('umath_scalbn_f32', 'umath_ldexp_f32'):
    sc = fn(lib, name, F, F, I64)
    bad = []
    for _ in range(6000):
        x = r32(random.choice([1, -1]) * 2.0 ** random.uniform(-149, 127))
        n = random.choice([random.randint(-300, 300), random.randint(-30, 30), 2 ** 40, -2 ** 40])
        want = rnd32(Fraction(x) * Fraction(2) ** n) if abs(n) < 1000 else (
            math.copysign(inf, x) if n > 0 else math.copysign(0.0, x))
        if not same(sc(x, n), want):
            bad.append((x, n, sc(x, n), want))
    for x in (0.0, -0.0, inf, -inf, nan):
        if not same(sc(x, 3), x):
            bad.append((x, 3))
    ck.check(f'{name} rounds once', not bad, bad[:1])

# --- fma -------------------------------------------------------------------------
fma64 = fn(lib, 'umath_fma_f64', D, D, D, D)
fma32 = fn(lib, 'umath_fma_f32', F, F, F, F)
bad64, bad32 = [], []
for i in range(20000):
    kind = i % 4
    if kind == 0:
        x, y, z = doubles(3)
    elif kind == 1:          # near-cancellation: z close to -x*y
        x, y = random.uniform(-10, 10), random.uniform(-10, 10)
        z = -(x * y) * (1 + random.choice([0, 1e-16, -1e-16, 2.2e-16]))
    elif kind == 2:          # subnormal / boundary results
        x = random.choice([1, -1]) * 2.0 ** random.uniform(-600, -400)
        y = random.choice([1, -1]) * 2.0 ** random.uniform(-650, -450)
        z = random.choice([0.0, 5e-324, -5e-324, random.uniform(-1e-310, 1e-310)])
    else:                    # overflow edge and wide exponent gaps
        x = random.choice([1, -1]) * 2.0 ** random.uniform(500, 520)
        y = random.choice([1, -1]) * 2.0 ** random.uniform(500, 510)
        z = random.choice([1, -1]) * 2.0 ** random.uniform(-1074, 1023)
    try:
        want = math.fma(x, y, z)
    except OverflowError:       # IEEE: +-Inf with the exact result's sign
        want = inf if Fraction(x) * Fraction(y) + Fraction(z) > 0 else -inf
    except ValueError:
        want = None
    if want is not None and not same(fma64(x, y, z), want):
        bad64.append((x, y, z, fma64(x, y, z), want))
    xf, yf, zf = r32(x if abs(x) < 1e30 else x * 1e-300), r32(y if abs(y) < 1e30 else y * 1e-300), r32(z)
    if kind == 1:
        xf, yf = r32(random.uniform(-10, 10)), r32(random.uniform(-10, 10))
        zf = r32(-(xf * yf) * (1 + random.choice([0, 1e-7, -1e-7, 6e-8])))
    if kind == 2:
        xf, yf = r32(random.choice([1, -1]) * 2.0 ** random.uniform(-80, -60)), r32(2.0 ** random.uniform(-80, -70))
        zf = r32(random.choice([0.0, 1.4e-45, -1.4e-45, random.uniform(-1e-39, 1e-39)]))
    if all(math.isfinite(v) for v in (xf, yf, zf)):
        q = Fraction(xf) * Fraction(yf) + Fraction(zf)
        w32 = rnd32(q)
        if q == 0:
            w32 = math.fma(xf, yf, zf)          # signed zero rules
        if not same(fma32(xf, yf, zf), w32):
            bad32.append((xf, yf, zf, fma32(xf, yf, zf), w32))
ck.check('fma_f64 is correctly rounded', not bad64, bad64[:1])
ck.check('fma_f32 is correctly rounded (no double rounding)', not bad32, bad32[:1])
spec = [((inf, 0.0, 1.0), nan), ((inf, 2.0, -inf), nan), ((1e308, 10.0, -inf), -inf), ((2.0, 3.0, inf), inf),
        ((nan, 1.0, 1.0), nan), ((1.0, 1.0, nan), nan), ((0.0, 5.0, -0.0), 0.0), ((-0.0, 5.0, -0.0), -0.0),
        ((1e308, 10.0, -1e308), inf), ((-1e308, 10.0, 1e308), -inf), ((1.0, 1.0, -1.0), 0.0)]
for (x, y, z), want in spec:
    ck.check('fma_f64 special values', same(fma64(x, y, z), want), f'fma{(x, y, z)} = {fma64(x, y, z)!r}, want {want!r}')
ck.check('fma_f64 keeps the low bits a separate multiply loses',
         fma64(1 + 2 ** -30, 1 + 2 ** -30, -(1 + 2 ** -29)) == 2 ** -60)

ck.finish()

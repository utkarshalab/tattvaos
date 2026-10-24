"""Special functions: erf, erfc, tgamma, lgamma (+ lgamma_r sign), polyval.

erf/erfc are checked against Python's math (accurate to about 1 ULP).
math.gamma/lgamma are not usable as references -- CPython's own versions
are off by up to millions of ULP next to lgamma's zeros -- so gamma is
checked against a 60-digit Decimal reference built here (Stirling's
series past z = 30 with exact Bernoulli numbers, the recurrence below, and
reflection with an exactly reduced sin(pi x) for x < 0). Negative-axis
lgamma is checked away from the points where |Gamma(x)| = 1, where every
reflection-based libm cancels. Gamma(n) = (n-1)! is checked exactly, and
polyval against Horner evaluation in the same order.
"""
import ctypes as C
import math
import random
import struct
from fractions import Fraction

from umath_ref import D, F, I32, P, Z, Checker, fn, load, r32, same, ulp_diff

lib = load()

# --- 60-digit reference for ln|Gamma| and Gamma -------------------------------
import decimal
from decimal import Decimal

decimal.getcontext().prec = 60
PI = Decimal('3.14159265358979323846264338327950288419716939937510582097494459230781640629')


def _bernoulli_even(count):
    a, out = [], []
    for m in range(2 * count + 1):
        a.append(Fraction(1, m + 1))
        for j in range(m, 0, -1):
            a[j - 1] = j * (a[j - 1] - a[j])
        if m >= 2 and m % 2 == 0:
            out.append((m, a[0]))
    return out


BERN = _bernoulli_even(22)


def _dec(q):
    return Decimal(q.numerator) / Decimal(q.denominator)


def _lgamma_pos(q):             # q: positive Fraction
    shift = Decimal(0)
    z = q
    while z < 30:
        shift += _dec(z).ln()
        z += 1
    d = _dec(z)
    s = (d - Decimal('0.5')) * d.ln() - d + (2 * PI).ln() / 2
    zp = d
    d2 = d * d
    for m, b in BERN:
        s += _dec(b) / (m * (m - 1) * zp)
        zp *= d2
    return s - shift


def _sinpi(q):                  # sin(pi q), q a Fraction
    r = q - 2 * round(q / 2)
    x = _dec(r) * PI
    term, s, k = x, x, 1
    while abs(term) > Decimal('1e-70'):
        term = -term * x * x / ((2 * k) * (2 * k + 1))
        s += term
        k += 1
    return s


def hp_lgamma(x):
    """(ln|Gamma(x)| as Decimal, sign of Gamma(x)) for finite non-pole x."""
    q = Fraction(x)
    if q > 0:
        return _lgamma_pos(q), 1
    s = _sinpi(q)               # Gamma(x) Gamma(1-x) = pi / sin(pi x)
    return PI.ln() - abs(s).ln() - _lgamma_pos(1 - q), (1 if s > 0 else -1)


def ref_lgamma(x):
    return float(hp_lgamma(x)[0])


def ref_gamma(x):
    v, sg = hp_lgamma(x)
    if v > Decimal(710):
        return sg * inf
    return sg * float(v.exp())

ck = Checker('special')
random.seed(53)
inf, nan = math.inf, math.nan


def sweep(name, f, ref, xs, bound, f32=False):
    worst, at = 0, None
    for x in xs:
        if x == 0:              # the poles/zeros are in the special-value table
            continue
        try:
            w = ref(x)
        except (ValueError, OverflowError):
            continue
        u = ulp_diff(f(x), w, f32)
        if u > worst:
            worst, at = u, x
    ck.check(f'{name} within {bound} ULP', worst <= bound, f'{worst} ULP at {at!r}')


def logu(lo, hi, n, s=1):
    return [s * 10.0 ** random.uniform(lo, hi) for _ in range(n)]


def uni(lo, hi, n):
    return [random.uniform(lo, hi) for _ in range(n)]


def lg_ok(x):
    return x != int(x) and abs(hp_lgamma(x)[0]) > Decimal('0.5')


CASES = {
    'erf': (math.erf, 3, uni(-7, 7, 6000) + uni(-1, 1, 3000) + logu(-310, 0, 1000) + logu(-310, 0, 500, -1)),
    'erfc': (math.erfc, 5, uni(-7, 28, 6000) + uni(0.3, 7, 4000) + logu(-310, 0, 1000) + uni(-1, 1, 1000)),
    'tgamma': (ref_gamma, 2, uni(0, 171.6, 1500) + uni(0, 5, 1000) + logu(-300, 0, 300)),
    'lgamma': (ref_lgamma, 3, uni(0, 5, 1500) + uni(0.999, 1.001, 400) + uni(1.999, 2.001, 400)
               + uni(5, 1e5, 500) + logu(5, 300, 300) + logu(-300, 0, 200)),
}
NEG = {
    'tgamma': (ref_gamma, 4, [x for x in uni(-184, 0, 1500) if x != int(x)]),
    'lgamma': (ref_lgamma, 4, [x for x in uni(-170, 0, 3000) if x != int(x) and lg_ok(x)]),
}
SPECIAL = {
    'erf': [(0.0, 0.0), (-0.0, -0.0), (inf, 1.0), (-inf, -1.0), (7.0, 1.0), (nan, nan), (1e-300, math.erf(1e-300))],
    'erfc': [(0.0, 1.0), (-0.0, 1.0), (inf, 0.0), (-inf, 2.0), (30.0, 0.0), (-30.0, 2.0), (nan, nan)],
    'tgamma': [(1.0, 1.0), (2.0, 1.0), (0.5, 1.772453850905516), (0.0, inf), (-0.0, -inf), (-1.0, nan),
               (-2.0, nan), (inf, inf), (-inf, nan), (172.0, inf), (nan, nan), (5e-324, inf)],
    'lgamma': [(1.0, 0.0), (2.0, 0.0), (0.0, inf), (-0.0, inf), (-1.0, inf), (-3.0, inf), (inf, inf),
               (-inf, inf), (nan, nan)],
}

for name, (ref, bound, xs) in CASES.items():
    for sfx, t, f32 in (('_f64', D, False), ('_f32', F, True)):
        f = fn(lib, f'umath_{name}{sfx}', t, t)
        vals = [r32(x) for x in xs] if f32 else xs
        if f32 and name == 'tgamma':
            vals = [v for v in vals if v < 35.0]
        sweep(f'{name}{sfx}', f, ref, vals, 1 if f32 else bound, f32)
        if name in NEG:
            nref, nbound, nxs = NEG[name]
            nvals = [r32(x) for x in nxs] if f32 else nxs
            if f32:
                nvals = [v for v in nvals if v > -38 and v != int(v) and (name != 'lgamma' or lg_ok(v))]
            sweep(f'{name}{sfx} for x < 0', f, nref, nvals, 2 if f32 else nbound, f32)
        for x, want in SPECIAL[name]:
            got = f(x)
            ck.check(f'{name}{sfx} special values', same(got, r32(want) if f32 else want),
                     f'{name}({x!r}) = {got!r}, want {want!r}')
        arr = fn(lib, f'umath_{name}{sfx}_array', None, P, P, Z)
        inp = fn(lib, f'umath_{name}{sfx}_inplace', None, P, Z)
        ct = C.c_float if f32 else C.c_double
        fmt = '<f' if f32 else '<d'
        for n in (0, 1, 3, 64):
            sel = [random.choice(vals[:2000] + [s for s, _ in SPECIAL[name]]) for _ in range(n)]
            src = (ct * max(n, 1))(*sel)
            dst = (ct * max(n, 1))()
            arr(C.addressof(dst), C.addressof(src), n)
            buf = (ct * max(n, 1))(*sel)
            inp(C.addressof(buf), n)
            want = [struct.pack(fmt, f(v)) for v in sel]
            ck.check(f'{name}{sfx}_array/inplace match the scalar',
                     [struct.pack(fmt, v) for v in dst[:n]] == want and [struct.pack(fmt, v) for v in buf[:n]] == want)

tg = fn(lib, 'umath_tgamma_f64', D, D)
ck.check('tgamma(n) = (n-1)! exactly up to 23!', all(tg(float(n)) == float(math.factorial(n - 1)) for n in range(1, 24)))
ck.check('tgamma(n) = (n-1)! within 1 ULP up to 170!',
         all(ulp_diff(tg(float(n)), float(math.factorial(n - 1))) <= 1 for n in range(1, 172)))

# lgamma_r: the sign of Gamma(x)
lgr = fn(lib, 'umath_lgamma_r_f64', D, D, P)
lgr32 = fn(lib, 'umath_lgamma_r_f32', F, F, P)
sgn = C.c_int32()
bad = []
for x in uni(-60, 60, 4000) + [-0.5, -1.5, -2.5, 0.0, -0.0, -1e-300, 1e-300, 3.0]:
    sgn.value = 99
    v = lgr(x, C.addressof(sgn))
    if x == 0:
        want = -1 if math.copysign(1, x) < 0 else 1
    elif x < 0 and x == int(x):
        want = 1
    else:
        want = 1 if math.gamma(x) > 0 or (x > 0) else -1
    if sgn.value != want:
        bad.append((x, sgn.value, want))
    if x != int(x) and not same(v, lgr(x, None)):
        bad.append((x, 'NULL sign changes the value'))
ck.check('lgamma_r_f64 sign of Gamma', not bad, bad[:1])
sgn.value = 99
lgr32(-0.5, C.addressof(sgn))
ck.check('lgamma_r_f32 sign of Gamma', sgn.value == -1)

# polyval: Horner against exact Fraction evaluation (one rounding per step)
pv = fn(lib, 'umath_polyval_f64', D, P, Z, D)
bad = []
for _ in range(3000):
    n = random.randint(0, 12)
    cs = [random.uniform(-10, 10) for _ in range(n)]
    x = random.uniform(-2, 2)
    arr = (C.c_double * max(n, 1))(*cs)
    acc = cs[0] if n else 0.0
    for c in cs[1:]:
        acc = acc * x + c                   # same operation order
    got = pv(C.addressof(arr), n, x)
    if not same(got, acc):
        bad.append((cs, x, got, acc))
ck.check('polyval_f64 is Horner (bit for bit)', not bad, bad[:1])

ck.finish()

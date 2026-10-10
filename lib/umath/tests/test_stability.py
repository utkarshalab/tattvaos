"""stability: compensated/pairwise sums, Welford, log-sum-exp.

References are exact: math.fsum (correctly rounded sum) and Fraction
arithmetic for mean/variance, so the tests also cover the ill-conditioned
inputs these algorithms exist for (cancellation, large offsets, overflow).
"""
import ctypes as C
import math
import random
from fractions import Fraction

from umath_ref import D, F, I64, P, U64, Z, Checker, fn, load, r32, same, ulp_diff

lib = load()
ck = Checker('stability')
random.seed(11)
EPS64, EPS32 = 2.0 ** -53, 2.0 ** -24
inf, nan = math.inf, math.nan


def arr(t, vals):
    return (t * len(vals))(*vals)


def datasets(f32=False):
    rnd = r32 if f32 else float
    yield 'uniform', [rnd(random.uniform(-1, 1)) for _ in range(1000)]
    yield 'cancel', [rnd(1e16 if not f32 else 1e8), 1.0, rnd(-1e16 if not f32 else -1e8)] * 50 + [rnd(3.25)]
    yield 'mixed magnitudes', [rnd(random.choice([1, -1]) * 10 ** random.uniform(-8, 8)) for _ in range(5000)]
    yield 'large n', [rnd(random.uniform(0, 1)) for _ in range(200001)]
    for n in (0, 1, 2, 3, 4, 5, 7, 8, 255, 256, 257, 513):
        yield f'n={n}', [rnd(random.uniform(-100, 100)) for _ in range(n)]


# --- Kahan (Neumaier): within ~2 ULP of the correctly rounded sum
for name, t, f32 in (('kahan_sum_f64', D, False), ('kahan_sum_f32', F, True)):
    f = fn(lib, f'umath_{name}', t, P, Z)
    for label, vals in datasets(f32):
        exact = math.fsum(vals)
        got = f(arr(t, vals), len(vals))
        ck.check(f'{name} near correctly rounded sum', ulp_diff(got, exact, f32) <= (1 if f32 else 2), f'{label}: {got!r} vs {exact!r}')

init = fn(lib, 'umath_kahan_init_f64', None, P)
add64, add32 = fn(lib, 'umath_kahan_add_f64', None, P, D), fn(lib, 'umath_kahan_add_f32', None, P, F)
res64, res32 = fn(lib, 'umath_kahan_result_f64', D, P), fn(lib, 'umath_kahan_result_f32', F, P)
for label, vals in datasets():
    st = (C.c_double * 2)()
    init(st)
    for v in vals:
        add64(st, v)
    ck.check('kahan streaming f64', ulp_diff(res64(st), math.fsum(vals)) <= 2, label)
st = (C.c_double * 2)()
init(st)
fvals = [r32(random.uniform(-1, 1)) for _ in range(999)]
for v in fvals:
    add32(st, v)
ck.check('kahan streaming f32', ulp_diff(res32(st), math.fsum(fvals), True) <= 1)

for name, t in (('kahan_sum_f64', D), ('kahan_sum_f32', F), ('pairwise_sum_f64', D), ('pairwise_sum_f32', F)):
    f = fn(lib, f'umath_{name}', t, P, Z)
    for vals, want in (([1.0, inf], inf), ([1.0, -inf, 2.0], -inf), ([inf, -inf], nan), ([1.0, nan], nan),
                       ([2.0] * 9 + [inf], inf)):
        ck.check(f'{name} non-finite', same(f(arr(t, vals), len(vals)), want), vals)
    ck.check(f'{name} empty', f(None, 0) == 0.0 and f(arr(t, [1.0]), 0) == 0.0)

# --- pairwise: error bounded by (leaf lane terms + log2 n) * eps * sum|x|
for name, t, f32, lane_terms in (('pairwise_sum_f64', D, False, 32), ('pairwise_sum_f32', F, True, 16)):
    f = fn(lib, f'umath_{name}', t, P, Z)
    eps = EPS32 if f32 else EPS64
    for label, vals in datasets(f32):
        if label == 'cancel':
            continue                    # pairwise makes no compensation promise
        exact = math.fsum(vals)
        bound = (lane_terms + 4 + math.log2(max(len(vals), 1))) * eps * math.fsum(abs(v) for v in vals) + 1e-300
        got = f(arr(t, vals), len(vals))
        ck.check(f'{name} error bound', abs(got - exact) <= bound, f'{label}: err {abs(got - exact):.3g} > {bound:.3g}')
    big = [r32(0.1) if f32 else 0.1] * 1_000_000
    exact = math.fsum(big)
    got = f(arr(t, big), len(big))
    ck.check(f'{name} 1e6 x 0.1 stays accurate', abs(got - exact) <= 64 * eps * exact, f'{got!r} vs {exact!r}')

# --- Welford: exact references with Fraction
def exact_stats(vals):
    fr = [Fraction(v) for v in vals]
    mean = sum(fr) / len(fr)
    return mean, sum((x - mean) ** 2 for x in fr)


winit = fn(lib, 'umath_welford_init', None, P)
upd64, upd32 = fn(lib, 'umath_welford_update_f64', None, P, P, Z), fn(lib, 'umath_welford_update_f32', None, P, P, Z)
push64, push32 = fn(lib, 'umath_welford_push_f64', None, P, D), fn(lib, 'umath_welford_push_f32', None, P, F)
merge = fn(lib, 'umath_welford_merge', None, P, P)
mean_of, var_of = fn(lib, 'umath_welford_mean', D, P), fn(lib, 'umath_welford_variance', D, P, U64)
count_of = fn(lib, 'umath_welford_count', U64, P)
State = C.c_ubyte * 24


def close(got, want, rel):
    want = float(want)
    return abs(got - want) <= rel * max(abs(want), 1e-300)


def mean_ok(got, mean, vals):
    # a mean's rounding error scales with the data's magnitude, not the mean's
    return abs(got - float(mean)) <= 8 * EPS64 * math.fsum(abs(v) for v in vals) / len(vals)


for f32 in (False, True):
    rnd = r32 if f32 else float
    t, upd, push = (F, upd32, push32) if f32 else (D, upd64, push64)
    tag = 'f32' if f32 else 'f64'
    cases = {
        'offset 1e9': [rnd(1e9 + random.gauss(0, 1)) for _ in range(5000)],
        'offset 1e4 (f32 range)': [rnd(1e4 + random.gauss(0, 0.01)) for _ in range(3000)],
        'uniform': [rnd(random.uniform(-5, 5)) for _ in range(777)],
        'n=1': [rnd(2.5)],
        'n=2': [rnd(1.0), rnd(3.0)],
        'constant': [rnd(7.25)] * 100,
    }
    for label, vals in cases.items():
        mean, m2 = exact_stats(vals)
        st = State()
        winit(st)
        upd(st, arr(t, vals), len(vals))
        ck.check(f'welford update_{tag} count', count_of(st) == len(vals), label)
        ck.check(f'welford update_{tag} mean', mean_ok(mean_of(st), mean, vals), (label, mean_of(st), float(mean)))
        if len(vals) > 1:
            var = m2 / (len(vals) - 1)
            ck.check(f'welford update_{tag} variance', close(var_of(st, 1), var, 1e-9) or (m2 == 0 and var_of(st, 1) == 0),
                     (label, var_of(st, 1), float(var)))
        st2 = State()
        winit(st2)
        for v in vals:
            push(st2, v)
        if len(vals) > 1:
            ck.check(f'welford push_{tag} variance', close(var_of(st2, 0), m2 / len(vals), 1e-7) or m2 == 0, label)
        # chunked updates merged together equal the whole
        parts, k = [], 0
        while k < len(vals):
            step = random.randint(1, max(1, len(vals) // 3))
            parts.append(vals[k:k + step])
            k += step
        total = State()
        winit(total)
        for part in parts:
            s = State()
            winit(s)
            upd(s, arr(t, part), len(part))
            merge(total, s)
        ck.check(f'welford merge_{tag} mean', mean_ok(mean_of(total), mean, vals), label)
        if len(vals) > 1:
            ck.check(f'welford merge_{tag} variance', close(var_of(total, 0), m2 / len(vals), 1e-9) or m2 == 0, label)

st = State()
winit(st)
ck.check('welford empty mean is NaN', math.isnan(mean_of(st)))
ck.check('welford variance NaN when count <= ddof', math.isnan(var_of(st, 0)))
push64(st, 4.0)
ck.check('welford one sample: population variance 0, sample variance NaN', var_of(st, 0) == 0.0 and math.isnan(var_of(st, 1)))
push64(st, nan)
ck.check('welford NaN sample propagates', math.isnan(mean_of(st)))

# --- log-sum-exp
def lse_ref(vals):
    m = max(vals)
    return m + math.log(math.fsum(math.exp(v - m) for v in vals))


for name, t, f32 in (('logsumexp_f64', D, False), ('logsumexp_f32', F, True)):
    f = fn(lib, f'umath_{name}', t, P, Z)
    rnd = r32 if f32 else float
    for vals in ([rnd(random.uniform(-10, 10)) for _ in range(500)], [rnd(random.uniform(-50, 50)) for _ in range(37)],
                 [1000.0, 1000.0], [-1000.0, -1000.0, -999.0], [0.0], [rnd(random.gauss(0, 3)) for _ in range(5)],
                 [rnd(80.0)] * 3 if f32 else [700.0] * 3):
        ck.check(f'{name} accuracy', ulp_diff(f(arr(t, vals), len(vals)), lse_ref(vals), f32) <= (1 if f32 else 4),
                 (vals[:3], f(arr(t, vals), len(vals)), lse_ref(vals)))
    # every remainder of both packed passes, NaN at every position
    for n in list(range(1, 20)) + [64, 1001]:
        vals = [rnd(random.uniform(-30, 30)) for _ in range(n)]
        got = f(arr(t, vals), n)
        ck.check(f'{name} accuracy by length', ulp_diff(got, lse_ref(vals), f32) <= (1 if f32 else 4), (n, got, lse_ref(vals)))
        for k in range(min(n, 9)):
            withnan = list(vals)
            withnan[k] = nan
            ck.check(f'{name} NaN at any position', math.isnan(f(arr(t, withnan), n)), (n, k))
        withinf = list(vals)
        withinf[-1] = inf
        ck.check(f'{name} +Inf at the end', f(arr(t, withinf), n) == inf, n)
    for vals, want in (([], -inf), ([nan, 1.0], nan), ([1.0, nan], nan), ([inf, 1.0], inf), ([-inf, -inf], -inf),
                       ([-inf, 0.0], 0.0), ([inf, nan], nan)):
        got = f(arr(t, vals) if vals else None, len(vals))
        ck.check(f'{name} special values', same(got, want), (vals, got))

ck.finish()

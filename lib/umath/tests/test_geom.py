"""geom: 2D affine transforms and Bezier curves (f64)."""
import ctypes as C
import math
import random

from umath_ref import D, I32, P, Z, Checker, fn, load

lib = load()
ck = Checker('geom')
random.seed(11)


class Pt(C.Structure):
    _fields_ = [('x', C.c_double), ('y', C.c_double)]


M6 = C.c_double * 6


def close(a, b, tol=1e-9):
    return abs(a - b) <= tol * max(1.0, abs(a), abs(b))


def apply_ref(m, x, y):
    a, b, c, d, e, f = m
    return a * x + c * y + e, b * x + d * y + f


def mul_ref(m1, m2):
    # out = m1 * m2: apply m2, then m1
    a1, b1, c1, d1, e1, f1 = m1
    a2, b2, c2, d2, e2, f2 = m2
    return [a1 * a2 + c1 * b2, b1 * a2 + d1 * b2, a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
            a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1]


def rand_m():
    return [random.uniform(-5, 5) for _ in range(6)]


# --- affine2 -----------------------------------------------------------------
ident = fn(lib, 'umath_affine2_identity', None, P)
trans = fn(lib, 'umath_affine2_translate', None, P, D, D)
scale = fn(lib, 'umath_affine2_scale', None, P, D, D)
rot = fn(lib, 'umath_affine2_rotate', None, P, D)
skew = fn(lib, 'umath_affine2_skew', None, P, D, D)
mul = fn(lib, 'umath_affine2_multiply', None, P, P, P)
det = fn(lib, 'umath_affine2_determinant', D, P)
inv = fn(lib, 'umath_affine2_invert', I32, P, P)
app = fn(lib, 'umath_affine2_apply', Pt, P, D, D)
appv = fn(lib, 'umath_affine2_apply_vector', Pt, P, D, D)
apparr = fn(lib, 'umath_affine2_apply_array', None, P, P, P, Z)

m = M6()
ident(m)
ck.check('identity', list(m) == [1, 0, 0, 1, 0, 0], list(m))
trans(m, 3.5, -2.0)
ck.check('translate', list(m) == [1, 0, 0, 1, 3.5, -2.0], list(m))
scale(m, 2.0, -0.5)
ck.check('scale', list(m) == [2.0, 0, 0, -0.5, 0, 0], list(m))
for ang in (0.0, 0.3, -1.2, math.pi / 2, math.pi, 7.0):
    rot(m, ang)
    want = [math.cos(ang), math.sin(ang), -math.sin(ang), math.cos(ang), 0, 0]
    ck.check('rotate', all(close(g, w, 1e-12) for g, w in zip(m, want)), (ang, list(m)))
for ax, ay in ((0.0, 0.0), (0.2, -0.4), (-1.0, 0.7)):
    skew(m, ax, ay)
    want = [1, math.tan(ay), math.tan(ax), 1, 0, 0]
    ck.check('skew', all(close(g, w, 1e-12) for g, w in zip(m, want)), (ax, ay, list(m)))
for _ in range(500):
    m1, m2 = rand_m(), rand_m()
    a, b, out = M6(*m1), M6(*m2), M6()
    mul(out, a, b)
    ck.check('multiply', all(close(g, w) for g, w in zip(out, mul_ref(m1, m2))), (m1, m2))
    mul(a, a, b)                        # aliasing the first input
    ck.check('multiply aliased', all(close(g, w) for g, w in zip(a, mul_ref(m1, m2))))
    a = M6(*m1)
    ck.check('determinant', close(det(a), m1[0] * m1[3] - m1[1] * m1[2]))
    x, y = random.uniform(-100, 100), random.uniform(-100, 100)
    p = app(a, x, y)
    wx, wy = apply_ref(m1, x, y)
    ck.check('apply', close(p.x, wx) and close(p.y, wy), (p.x, p.y, wx, wy))
    v = appv(a, x, y)
    ck.check('apply_vector', close(v.x, wx - m1[4]) and close(v.y, wy - m1[5]))
    r = M6()
    if abs(m1[0] * m1[3] - m1[1] * m1[2]) > 1e-3:
        ck.check('invert ok', inv(r, a) == 0)
        prod = M6()
        mul(prod, a, r)
        ck.check('m * inverse = identity',
                 all(abs(g - w) < 1e-8 for g, w in zip(prod, [1, 0, 0, 1, 0, 0])), list(prod))
        inv(a, a)                       # in place
        ck.check('invert aliased', all(close(g, w) for g, w in zip(a, r)))
for sing in ([1, 2, 2, 4, 5, 6], [0, 0, 0, 0, 1, 1], [math.nan, 0, 0, 1, 0, 0], [1e308, 1e308, -1e308, 1e308, 0, 0]):
    r = M6(9, 9, 9, 9, 9, 9)
    rc = inv(r, M6(*sing))
    ck.check('invert singular', rc == -1 and list(r) == [9] * 6 or (rc == 0 and all(math.isfinite(v) for v in r)), sing)
for n in (0, 1, 3, 17):
    m1 = rand_m()
    src = (C.c_double * (2 * n + 2))(*[random.uniform(-50, 50) for _ in range(2 * n + 2)])
    dst = (C.c_double * (2 * n + 2))()
    apparr(M6(*m1), dst, src, n)
    ok = all(close(dst[2 * i], apply_ref(m1, src[2 * i], src[2 * i + 1])[0]) and
             close(dst[2 * i + 1], apply_ref(m1, src[2 * i], src[2 * i + 1])[1]) for i in range(n))
    ck.check('apply_array', ok and dst[2 * n] == 0, n)
    apparr(M6(*m1), src, src, n)        # in place
    ck.check('apply_array in place', all(close(src[i], dst[i]) for i in range(2 * n)), n)

# --- bezier ------------------------------------------------------------------
Q, Cu = C.c_double * 6, C.c_double * 8
qe = fn(lib, 'umath_bezier_quad_eval', Pt, P, D)
ce = fn(lib, 'umath_bezier_cubic_eval', Pt, P, D)
qt = fn(lib, 'umath_bezier_quad_tangent', Pt, P, D)
ct = fn(lib, 'umath_bezier_cubic_tangent', Pt, P, D)
qs = fn(lib, 'umath_bezier_quad_split', None, P, D, P)
cs = fn(lib, 'umath_bezier_cubic_split', None, P, D, P)
qn = fn(lib, 'umath_bezier_quad_segments', Z, P, D)
cn = fn(lib, 'umath_bezier_cubic_segments', Z, P, D)


def bern(pts, t):
    n = len(pts) - 1
    x = sum(math.comb(n, i) * (1 - t) ** (n - i) * t ** i * pts[i][0] for i in range(n + 1))
    y = sum(math.comb(n, i) * (1 - t) ** (n - i) * t ** i * pts[i][1] for i in range(n + 1))
    return x, y


def deriv(pts):
    n = len(pts) - 1
    return [(n * (pts[i + 1][0] - pts[i][0]), n * (pts[i + 1][1] - pts[i][1])) for i in range(n)]


def max_dev(pts, segs):
    """Largest distance from the curve to its n-segment polyline (sampled)."""
    worst = 0.0
    for s in range(segs):
        t0, t1 = s / segs, (s + 1) / segs
        a, b = bern(pts, t0), bern(pts, t1)
        for k in range(1, 16):
            t = t0 + (t1 - t0) * k / 16
            p = bern(pts, t)
            lx, ly = a[0] + (b[0] - a[0]) * k / 16, a[1] + (b[1] - a[1]) * k / 16
            worst = max(worst, math.hypot(p[0] - lx, p[1] - ly))
    return worst


for deg, T, ev, tg, sp, sn, npts in ((2, Q, qe, qt, qs, qn, 3), (3, Cu, ce, ct, cs, cn, 4)):
    name = 'quad' if deg == 2 else 'cubic'
    for _ in range(400):
        pts = [(random.uniform(-200, 200), random.uniform(-200, 200)) for _ in range(npts)]
        arr = T(*[c for p in pts for c in p])
        t = random.random()
        g, w = ev(arr, t), bern(pts, t)
        ck.check(f'{name}_eval', close(g.x, w[0]) and close(g.y, w[1]), (pts, t))
        g, w = tg(arr, t), bern(deriv(pts), t)
        ck.check(f'{name}_tangent', close(g.x, w[0]) and close(g.y, w[1]), (pts, t))
        out = (C.c_double * (2 * (2 * npts - 1)))()
        sp(arr, t, out)
        o = [(out[2 * i], out[2 * i + 1]) for i in range(2 * npts - 1)]
        left, right = o[:npts], o[npts - 1:]
        ok = True
        for u in (0.0, 0.25, 0.5, 0.9, 1.0):
            lp, rp = bern(left, u), bern(right, u)
            wl, wr = bern(pts, t * u), bern(pts, t + (1 - t) * u)
            ok &= close(lp[0], wl[0], 1e-8) and close(lp[1], wl[1], 1e-8)
            ok &= close(rp[0], wr[0], 1e-8) and close(rp[1], wr[1], 1e-8)
        ck.check(f'{name}_split halves trace the curve', ok, (pts, t))
        ck.check(f'{name}_split endpoints', o[0] == pts[0] and o[-1] == pts[-1])
    for _ in range(150):
        pts = [(random.uniform(-300, 300), random.uniform(-300, 300)) for _ in range(npts)]
        arr = T(*[c for p in pts for c in p])
        for tol in (0.05, 0.25, 1.0, 4.0):
            n = sn(arr, tol)
            ck.check(f'{name}_segments within tol', 1 <= n <= 4096 and max_dev(pts, n) <= tol * 1.0001,
                     (pts, tol, n, max_dev(pts, n)))
            L = max(math.hypot(pts[i][0] - 2 * pts[i + 1][0] + pts[i + 2][0],
                               pts[i][1] - 2 * pts[i + 1][1] + pts[i + 2][1]) for i in range(npts - 2))
            want = min(max(math.ceil(math.sqrt(deg * (deg - 1) / 8 * L / tol)), 1), 4096)
            ck.check(f'{name}_segments = Wang', abs(n - want) <= 1, (n, want))
    line = T(*[c for i in range(npts) for c in (i * 10.0, i * 5.0)])
    ck.check(f'{name}_segments straight line', sn(line, 0.1) == 1)
    big = T(*[c for i in range(npts) for c in ((-1) ** i * 1e9, 0.0)])
    ck.check(f'{name}_segments capped', sn(big, 1e-6) == 4096)
    for bad in (0.0, -1.0, math.nan):
        ck.check(f'{name}_segments bad tol', sn(line, bad) == 1, bad)
    nanpts = T(*([math.nan] * (2 * npts)))
    ck.check(f'{name}_segments NaN points', sn(nanpts, 0.5) == 1)

# --- tight bounds -----------------------------------------------------------
qb = fn(lib, 'umath_bezier_quad_bounds', None, P, P)
cb = fn(lib, 'umath_bezier_cubic_bounds', None, P, P)


def lerp(a, b, t):
    return a + (b - a) * t


def quad_bounds_ref(p):
    out = [0.0] * 4
    for k in (0, 1):
        p0, p1, p2 = p[k], p[k + 2], p[k + 4]
        lo, hi = min(p0, p2), max(p0, p2)
        den = p0 - p1 * 2 + p2
        if den != 0:
            t = (p0 - p1) / den
            if 0 < t < 1:
                v = lerp(lerp(p0, p1, t), lerp(p1, p2, t), t)
                lo, hi = min(lo, v), max(hi, v)
        out[k], out[k + 2] = lo, hi
    return out


def cubic_bounds_ref(p):
    out = [0.0] * 4
    for k in (0, 1):
        p0, p1, p2, p3 = p[k], p[k + 2], p[k + 4], p[k + 6]
        lo, hi = min(p0, p3), max(p0, p3)
        c0, c1, c2 = p1 - p0, p2 - p1, p3 - p2
        A = c0 - (c1 + c1) + c2
        B = (c1 - c0) + (c1 - c0)
        ts = []
        if A == 0:
            if B != 0:
                ts.append((0.0 - c0) / B)
        else:
            disc = B * B - ((A * c0) + (A * c0)) * 2
            if disc >= 0:
                r = disc ** 0.5
                ts += [((0.0 - B) + r) / (A + A), ((0.0 - B) - r) / (A + A)]
        for t in ts:
            if 0 < t < 1:
                a, b, c = lerp(p0, p1, t), lerp(p1, p2, t), lerp(p2, p3, t)
                v = lerp(lerp(a, b, t), lerp(b, c, t), t)
                lo, hi = min(lo, v), max(hi, v)
        out[k], out[k + 2] = lo, hi
    return out


for trial in range(3000):
    n = 6 if trial % 2 else 8
    pts = [random.uniform(-100, 100) for _ in range(n)]
    if trial % 7 == 0:          # a line, a repeated point, a straight cubic
        pts[2], pts[3] = pts[0], pts[1]
    arr, out = (C.c_double * n)(*pts), (C.c_double * 4)()
    (cb if n == 8 else qb)(arr, out)
    want = (cubic_bounds_ref if n == 8 else quad_bounds_ref)(pts)
    name = 'cubic' if n == 8 else 'quad'
    ck.check(f'{name}_bounds matches the reference', list(out) == want, (trial, list(out), want))
    # every point of the curve lies inside, and the box's edges are reached
    ev = ce if n == 8 else qe
    xs, ys = [], []
    for i in range(401):
        q = ev(arr, i / 400)
        xs.append(q.x)
        ys.append(q.y)
    span = max(1.0, out[2] - out[0], out[3] - out[1])
    inside = min(xs) >= out[0] - 1e-9 * span and max(xs) <= out[2] + 1e-9 * span and \
        min(ys) >= out[1] - 1e-9 * span and max(ys) <= out[3] + 1e-9 * span
    ck.check(f'{name}_bounds contain the curve', inside, trial)
    # tight: sampling at 1/400 comes within the curvature-limited gap
    tight = min(xs) - out[0] <= 1e-3 * span and out[2] - max(xs) <= 1e-3 * span and \
        min(ys) - out[1] <= 1e-3 * span and out[3] - max(ys) <= 1e-3 * span
    ck.check(f'{name}_bounds are tight', tight, trial)

# --- arc ---------------------------------------------------------------------
arcpt = fn(lib, 'umath_arc_point', Pt, D, D, D, D, D)
arcc = fn(lib, 'umath_arc_to_cubics', Z, P, D, D, D, D, D, D)
for _ in range(400):
    cx, cy = random.uniform(-100, 100), random.uniform(-100, 100)
    rx, ry = random.uniform(0.1, 80), random.uniform(0.1, 80)
    start, sweep = random.uniform(-7, 7), random.choice([random.uniform(-7, 7), 0.01, -math.pi / 2, math.tau])
    p = arcpt(cx, cy, rx, ry, start)
    ck.check('arc_point', close(p.x, cx + rx * math.cos(start)) and close(p.y, cy + ry * math.sin(start)))
    out = (C.c_double * 24)()
    n = arcc(out, cx, cy, rx, ry, start, sweep)
    sw = max(-math.tau, min(math.tau, sweep))
    want_n = max(1, min(4, math.ceil(abs(sw) / (math.pi / 2) - 1e-12)))
    ck.check('arc_to_cubics count', n == want_n, (sweep, n, want_n))
    prev = (cx + rx * math.cos(start), cy + ry * math.sin(start))
    worst = 0.0
    for i in range(n):
        seg = [prev] + [(out[6 * i + 2 * k], out[6 * i + 2 * k + 1]) for k in range(3)]
        for s in range(1, 32):
            x, y = bern(seg, s / 32)
            # distance from the ellipse, measured in the unit-circle frame
            worst = max(worst, abs(math.hypot((x - cx) / rx, (y - cy) / ry) - 1.0))
        prev = seg[-1]
    end = (cx + rx * math.cos(start + sw), cy + ry * math.sin(start + sw))
    ck.check('arc_to_cubics on the ellipse', worst < 3e-4, (worst, sweep))
    ck.check('arc_to_cubics ends at start + sweep',
             math.hypot(prev[0] - end[0], prev[1] - end[1]) < 1e-9 * max(1, rx, ry, abs(cx), abs(cy)))
for bad in (0.0, math.nan):
    ck.check('arc_to_cubics empty sweep', arcc((C.c_double * 24)(), 0, 0, 1, 1, 0, bad) == 0, bad)

# --- SVG arcs (end points, rotation, flags) ----------------------------------
arcsvg = fn(lib, 'umath_arc_svg_to_cubics', Z, P, D, D, D, D, D, D, D, I32)


def svg_arc_ref(x1, y1, x2, y2, rx, ry, phi, large, sweep):
    """SVG 1.1 F.6.5-F.6.6: centre, radii, start angle, sweep."""
    rx, ry = abs(rx), abs(ry)
    c, s = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    xp, yp = c * dx + s * dy, -s * dx + c * dy
    lam = (xp / rx) ** 2 + (yp / ry) ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * yp * yp - ry * ry * xp * xp
    coef = 0.0 if lam > 1 else math.sqrt(max(0.0, num / (rx * rx * yp * yp + ry * ry * xp * xp)))
    if large == sweep:
        coef = -coef
    cxp, cyp = coef * rx * yp / ry, -coef * ry * xp / rx
    cx, cy = c * cxp - s * cyp + (x1 + x2) / 2, s * cxp + c * cyp + (y1 + y2) / 2
    ux, uy = (xp - cxp) / rx, (yp - cyp) / ry
    vx, vy = (-xp - cxp) / rx, (-yp - cyp) / ry
    t1 = math.atan2(uy, ux)
    dt = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    if sweep and dt < 0:
        dt += math.tau
    elif not sweep and dt > 0:
        dt -= math.tau
    return cx, cy, rx, ry, t1, dt


for trial in range(600):
    x1, y1, x2, y2 = (random.uniform(-50, 50) for _ in range(4))
    rx, ry = random.uniform(0.5, 60) * random.choice([1, -1]), random.uniform(0.5, 60)
    if trial % 7 == 0:
        rx, ry = 0.01, 0.02                     # far too small: scaled up
    phi = random.uniform(-4, 4)
    large, sweep = trial & 1, (trial >> 1) & 1
    out = (C.c_double * 24)()
    n = arcsvg(out, x1, y1, x2, y2, rx, ry, phi, large | sweep << 1)
    cx, cy, rrx, rry, t1, dt = svg_arc_ref(x1, y1, x2, y2, rx, ry, phi, large, sweep)
    want_n = max(1, min(4, math.ceil(abs(dt) / (math.pi / 2) - 1e-12)))
    ck.check('arc_svg count', n == want_n, (trial, n, want_n, dt))
    if trial % 7 == 0:
        ck.check('arc_svg scaled radii: a half ellipse', abs(abs(dt) - math.pi) == 0.0, (trial, dt))
    ck.check('arc_svg ends exactly at p2', out[6 * n - 2] == x2 and out[6 * n - 1] == y2, trial)
    c, s = math.cos(phi), math.sin(phi)
    prev, worst = (x1, y1), 0.0
    for i in range(n):
        seg = [prev] + [(out[6 * i + 2 * k], out[6 * i + 2 * k + 1]) for k in range(3)]
        for t in range(1, 32):
            px, py = bern(seg, t / 32)
            lx, ly = c * (px - cx) + s * (py - cy), -s * (px - cx) + c * (py - cy)
            worst = max(worst, abs(math.hypot(lx / rrx, ly / rry) - 1.0))
        prev = seg[-1]
    ck.check('arc_svg on the ellipse', worst < 3e-4, (trial, worst))
    # the direction: the curve's first handle leaves p1 on the sweep's side
    tx, ty = out[0] - x1, out[1] - y1
    rad_x, rad_y = x1 - cx, y1 - cy
    turn = rad_x * ty - rad_y * tx
    ck.check('arc_svg direction', (turn > 0) == bool(sweep) or abs(turn) < 1e-9, (trial, turn, sweep))
out = (C.c_double * 24)()
ck.check('arc_svg equal end points', arcsvg(out, 3, 4, 3, 4, 5, 5, 0, 0) == 0)
n = arcsvg(out, 1, 2, 7, 5, 0, 5, 0.3, 3)
ck.check('arc_svg zero radius is a line', n == 1 and list(out[:6]) == [1, 2, 7, 5, 7, 5], list(out[:6]))
n = arcsvg(out, 1, 2, 7, 5, 4, 0, 0, 0)
ck.check('arc_svg zero ry is a line', n == 1 and list(out[:6]) == [1, 2, 7, 5, 7, 5], list(out[:6]))
n = arcsvg(out, 0, 0, 10, 0, 5, 5, 0, 0)      # a half circle, centre (5, 0)
ck.check('arc_svg half circle', n == 2 and abs(out[4] - 5) < 1e-12 and abs(abs(out[5]) - 5) < 1e-12, list(out[:12]))

ck.finish()

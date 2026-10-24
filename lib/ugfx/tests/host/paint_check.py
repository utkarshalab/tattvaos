#!/usr/bin/env python3
"""Check ugfx paints: linear, radial, two-circle radial and conic gradients,
image patterns, spreads and extend modes, stops, paint transforms and
compositing under anti-aliased coverage.

Usage: paint_check.py <host_path binary> [--seed N]

The reference builds the same 1024-entry table from the stops (positions
clamped to [0, 1] and to the previous stop, colours interpolated
premultiplied, rounded to nearest), maps each pixel centre through the
inverse paint transform to t, applies the spread, and picks the entry
round(t * 1023). For two-circle gradients t is the larger root of
|p - c(t)| = r(t) with r(t) >= 0 (each chosen t is checked against that
equation), and pixels on no circle stay unpainted. Image patterns are
sampled the same way: the pixel centre in image space, clamped to
+/- 2^52, nearest (floor) or bilinear (around p - 0.5, weights summed in
ugfx's order, rounded to nearest), each axis wrapped by its extend mode. The shape's coverage comes from filling it once in solid
white over transparent black; the expected pixel is that coverage applied
to the gradient colour, composited source-over onto the background with
ugfx's exact rounding. Each channel must match within 1, except a few
pixels where t lands on a table boundary or a conic seam.

Development-machine tooling only; not part of any OS image.
"""
import math
import os
import random
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from path_check import run_tool, script  # noqa: E402

LUT = 1024
PAD, REPEAT, REFLECT = 0, 1, 2
LINEAR, RADIAL, CONIC, RADIAL2 = 1, 2, 3, 4
NONE = 3
NEAREST, BILINEAR = 0, 1


def lut(stops):
    offs, cols = [], []
    prev = 0.0
    for o, c in stops:
        o = min(max(o, prev), 1.0)
        prev = o
        a = (c >> 24) & 255
        offs.append(o)
        cols.append([((c >> s) & 255) * (a / 255) for s in (0, 8, 16)] + [float(a)])
    table = np.zeros(LUT, np.int64)
    j = 0
    for i in range(LUT):
        t = i / 1023.0
        while j + 1 < len(offs) and t >= offs[j + 1]:
            j += 1
        if t < offs[j] or j + 1 >= len(offs):
            ch = cols[j]
        else:
            f = (t - offs[j]) / (offs[j + 1] - offs[j])
            ch = [a + (b - a) * f for a, b in zip(cols[j], cols[j + 1])]
        v = 0
        for k, x in enumerate(ch):
            v |= int(round(x)) << (8 * k)
        table[i] = v
    return table


def invert(m):
    a, b, c, d, e, f = m
    det = a * d - b * c
    return [d / det, -b / det, -c / det, a / det, (c * f - d * e) / det, (b * e - a * f) / det]


def colours(w, h, kind, spread, geom, stops, matrix):
    table = lut(stops)
    inv = invert(matrix) if matrix else [1, 0, 0, 1, 0, 0]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    xs += 0.5
    ys += 0.5
    px = inv[0] * xs + inv[2] * ys + inv[4]
    py = inv[1] * xs + inv[3] * ys + inv[5]
    if kind == LINEAR:
        x0, y0, x1, y1 = geom
        dx, dy = x1 - x0, y1 - y0
        L2 = dx * dx + dy * dy
        t = (px - x0) * (dx / L2) + (py - y0) * (dy / L2)
    elif kind == RADIAL:
        cx, cy, r = geom[:3]
        t = np.sqrt((px - cx) ** 2 + (py - cy) ** 2) * (1.0 / r)
    elif kind == RADIAL2:
        t, painted = radial2_t(px, py, *geom)
    else:
        cx, cy, start = geom[:3]
        t = np.arctan2(py - cy, px - cx) * (1 / (2 * math.pi)) - start * (1 / (2 * math.pi))
        t = t - np.floor(t)
        spread = PAD
    if spread == REPEAT:
        t = t - np.floor(t)
    elif spread == REFLECT:
        u = t * 0.5
        u = (u - np.floor(u)) * 2
        t = np.where(u > 1, 2 - u, u)
    t = np.clip(np.nan_to_num(t, nan=0.0), 0, 1)
    out = table[(t * 1023 + 0.5).astype(np.int64)]
    if kind == RADIAL2:
        out = np.where(painted, out, 0)
    return out


def radial2_t(px, py, x0, y0, r0, x1, y1, r1):
    """Largest t with |p - c(t)| = r(t), r(t) >= 0; and where one exists."""
    dx, dy, dr = x1 - x0, y1 - y0, r1 - r0
    qx, qy = px - x0, py - y0
    a = dx * dx + dy * dy - dr * dr
    b = qx * dx + qy * dy + r0 * dr
    c = qx * qx + qy * qy - r0 * r0
    with np.errstate(all='ignore'):
        if a == 0:
            t = np.where(b != 0, c / (2 * b), np.nan)
            ok = (b != 0) & (r0 + t * dr >= 0)
        else:
            disc = b * b - a * c
            s = np.sqrt(np.maximum(disc, 0))
            t1, t2 = (b + s) / a, (b - s) / a
            hi, lo = np.maximum(t1, t2), np.minimum(t1, t2)
            hi_ok = r0 + hi * dr >= 0
            lo_ok = r0 + lo * dr >= 0
            t = np.where(hi_ok, hi, lo)
            ok = (disc >= 0) & (hi_ok | lo_ok)
    # the reference's own check: the circle at t passes through p
    tt = np.where(ok, t, 0)
    resid = np.hypot(qx - tt * dx, qy - tt * dy) - (r0 + tt * dr)
    scale = 1 + np.abs(tt) * (abs(dx) + abs(dy) + abs(dr)) + abs(r0)
    assert np.all(np.abs(np.where(ok, resid, 0)) <= 1e-6 * scale), "radial2 reference"
    return np.where(ok, t, 0.0), ok


def wrap(i, size, mode):
    """Index per extend mode, -1 outside for NONE."""
    if mode == REPEAT:
        return np.mod(i, size)
    if mode == REFLECT:
        m = np.mod(i, 2 * size)
        return np.where(m >= size, 2 * size - 1 - m, m)
    if mode == NONE:
        return np.where((i < 0) | (i >= size), -1, i)
    return np.clip(i, 0, size - 1)


def texel(img, i, j, ex, ey):
    h, w = img.shape
    ii, jj = wrap(i, w, ex), wrap(j, h, ey)
    ok = (ii >= 0) & (jj >= 0)
    return np.where(ok, img[np.maximum(jj, 0), np.maximum(ii, 0)], 0)


def image_colours(w, h, img, ex, ey, filt, matrix):
    inv = invert(matrix) if matrix else [1, 0, 0, 1, 0, 0]
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    xs += 0.5
    ys += 0.5
    u = inv[0] * xs + inv[2] * ys + inv[4]
    v = inv[1] * xs + inv[3] * ys + inv[5]
    lim = 2.0 ** 52

    def fl(x):
        x = np.minimum(np.maximum(np.nan_to_num(x, nan=-lim), -lim), lim)
        f = np.floor(x)
        return f, f.astype(np.int64)

    if filt == NEAREST:
        return texel(img, fl(u)[1], fl(v)[1], ex, ey)
    u, v = u - 0.5, v - 0.5
    (fu, i), (fv, j) = fl(u), fl(v)
    fx, fy = np.minimum(np.maximum(u, -lim), lim) - fu, np.minimum(np.maximum(v, -lim), lim) - fv
    t = [texel(img, i, j, ex, ey), texel(img, i + 1, j, ex, ey),
         texel(img, i, j + 1, ex, ey), texel(img, i + 1, j + 1, ex, ey)]
    wts = [(1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy]
    out = np.zeros(u.shape, np.int64)
    for k in range(4):
        acc = ((t[0] >> (8 * k)) & 255) * wts[0]
        acc = acc + ((t[1] >> (8 * k)) & 255) * wts[1]
        acc = acc + ((t[2] >> (8 * k)) & 255) * wts[2]
        acc = acc + ((t[3] >> (8 * k)) & 255) * wts[3]
        out |= np.rint(acc).astype(np.int64) << (8 * k)
    return out


def random_image(rng, w, h):
    img = np.zeros((h, w), np.int64)
    for y in range(h):
        for x in range(w):
            a = rng.choice([255, 255, rng.randint(0, 255)])
            b, g, r = (rng.randint(0, a) for _ in range(3))
            img[y, x] = b | g << 8 | r << 16 | a << 24
    return img


def image_cases(rng):
    W, H = 48, 32
    full = [('rect', 0, 0, W, H)]
    img = random_image(rng, 7, 5)
    rot = [math.cos(0.5) * 3, math.sin(0.5) * 3, -math.sin(0.5) * 3, math.cos(0.5) * 3, 18, 2]
    yield "image pad", full, img, PAD, PAD, NEAREST, [1, 0, 0, 1, 10, 8]
    yield "image repeat", full, img, REPEAT, REPEAT, NEAREST, None
    yield "image reflect", full, img, REFLECT, REFLECT, NEAREST, [1, 0, 0, 1, -3, -2]
    yield "image none", full, img, NONE, NONE, NEAREST, [1, 0, 0, 1, 20, 12]
    yield "image mixed", full, img, REPEAT, PAD, NEAREST, [1, 0, 0, 1, 5, 10]
    yield "image none/reflect", full, img, NONE, REFLECT, NEAREST, [1, 0, 0, 1, 12, 0]
    yield "nearest 4x", full, img, REPEAT, REFLECT, NEAREST, [4, 0, 0, 4, 2, 1]
    yield "bilinear 4x", full, img, REPEAT, REFLECT, BILINEAR, [4, 0, 0, 4, 2, 1]
    yield "bilinear pad", full, img, PAD, PAD, BILINEAR, [5, 0, 0, 5, 6, 4]
    yield "bilinear none", full, img, NONE, NONE, BILINEAR, [4.5, 0, 0, 4.5, 8.25, 5.75]
    yield "bilinear identity", full, img, REPEAT, REPEAT, BILINEAR, None
    yield "bilinear half shift", full, img, REPEAT, REPEAT, BILINEAR, [1, 0, 0, 1, 0.5, 0.25]
    yield "bilinear rotated", full, img, REPEAT, REPEAT, BILINEAR, rot
    yield "nearest rotated", full, img, REFLECT, NONE, NEAREST, rot
    yield "bilinear down", full, random_image(rng, 30, 20), REFLECT, REPEAT, BILINEAR, [0.37, 0, 0, 0.41, 3, 1]
    yield "skewed", full, img, REPEAT, REPEAT, BILINEAR, [3, 0, 1.5, 3, 0, 0]
    yield "far away", full, img, REPEAT, REFLECT, BILINEAR, [2, 0, 0, 2, -1e7, 3e6]
    yield "1x1 image", full, random_image(rng, 1, 1), REPEAT, NONE, BILINEAR, [6, 0, 0, 6, 20, 10]
    yield "circle over bg", [('circle', 24, 16, 13.3)], img, REPEAT, REPEAT, BILINEAR, [3, 0, 0, 3, 1, 1]
    for i in range(6):
        im = random_image(rng, rng.randint(1, 9), rng.randint(1, 9))
        s, a = rng.uniform(0.5, 6), rng.uniform(-3, 3)
        m = [s * math.cos(a), s * math.sin(a), -s * math.sin(a) * rng.uniform(0.5, 1.5), s * math.cos(a),
             rng.uniform(-20, 40), rng.uniform(-20, 30)]
        shape = [('ellipse', rng.uniform(10, 38), rng.uniform(8, 24), rng.uniform(5, 20), rng.uniform(4, 14))]
        yield (f"random image {i}", shape, im, rng.choice([PAD, REPEAT, REFLECT, NONE]),
               rng.choice([PAD, REPEAT, REFLECT, NONE]), rng.choice([NEAREST, BILINEAR]), m)


def div255(x):
    x = x + 128
    return (x + (x >> 8)) >> 8


def composite(col, cov, bg):
    out = np.zeros(col.shape, np.int64)
    s = [div255(((col >> (8 * k)) & 255) * cov) for k in range(4)]
    inv_a = 255 - s[3]
    for k in range(4):
        d = (bg >> (8 * k)) & 255
        out |= (s[k] + div255(d * inv_a)) << (8 * k)
    return np.where(cov == 0, bg, out)


def pack(px):
    return px[..., 0] | (px[..., 1] << 8) | (px[..., 2] << 16) | (px[..., 3] << 24)


def gradient_cases(rng):
    W, H = 48, 32
    full = [('rect', 0, 0, W, H)]
    two = [(0.0, 0xFFFF0000), (1.0, 0xFF0000FF)]
    three = [(0.0, 0xFFFF0000), (0.5, 0xFF00FF00), (1.0, 0xFF0000FF)]
    yield "linear pad", W, H, full, LINEAR, PAD, [8, 0, 40, 0], two, None
    yield "linear diagonal", W, H, full, LINEAR, PAD, [0, 0, 48, 32], three, None
    yield "linear repeat", W, H, full, LINEAR, REPEAT, [10, 4, 22, 12], three, None
    yield "linear reflect", W, H, full, LINEAR, REFLECT, [10, 4, 22, 12], three, None
    yield "linear reversed", W, H, full, LINEAR, REPEAT, [40, 30, 30, 2], two, None
    yield "to transparent", W, H, full, LINEAR, PAD, [0, 0, 48, 0], [(0, 0xFFFFFFFF), (1, 0x00FF0000)], None
    yield "translucent stops", W, H, full, LINEAR, PAD, [0, 0, 0, 32], [(0, 0x80FF8000), (1, 0x2000FFFF)], None
    yield "hard edge", W, H, full, LINEAR, PAD, [0, 0, 48, 0], [(0, 0xFFFF0000), (0.5, 0xFFFF0000), (0.5, 0xFF0000FF), (1, 0xFF00FF00)], None
    yield "unordered offsets", W, H, full, LINEAR, PAD, [0, 0, 48, 0], [(0.6, 0xFFFF0000), (0.2, 0xFF00FF00), (0.9, 0xFF0000FF)], None
    yield "offsets outside", W, H, full, LINEAR, PAD, [0, 0, 48, 0], [(-0.5, 0xFFFF0000), (0.3, 0xFFFFFF00), (1.7, 0xFF0000FF)], None
    yield "inner stops only", W, H, full, LINEAR, REPEAT, [0, 0, 48, 0], [(0.3, 0xFFFF0000), (0.7, 0xFF0000FF)], None
    yield "single stop", W, H, full, LINEAR, PAD, [0, 0, 48, 0], [(0.4, 0xC0336699)], None
    yield "radial pad", W, H, full, RADIAL, PAD, [24, 16, 14, 0], three, None
    yield "radial repeat", W, H, full, RADIAL, REPEAT, [20, 12, 6.5, 0], two, None
    yield "radial reflect", W, H, full, RADIAL, REFLECT, [20, 12, 6.5, 0], three, None
    yield "conic", W, H, full, CONIC, PAD, [24, 16, 0, 0], three + [(1.0, 0xFFFF0000)], None
    yield "conic start", W, H, full, CONIC, PAD, [20, 18, 1.1, 0], [(0, 0xFF000000), (1, 0xFFFFFFFF)], None
    rot = [math.cos(0.6) * 0.8, math.sin(0.6) * 0.8, -math.sin(0.6) * 0.8, math.cos(0.6) * 0.8, 20, 6]
    yield "linear transformed", W, H, full, LINEAR, REFLECT, [0, 0, 10, 0], three, rot
    yield "radial ellipse", W, H, full, RADIAL, PAD, [0, 0, 1, 0], three, [20, 0, 0, 12, 24, 16]
    yield "conic skewed", W, H, full, CONIC, PAD, [0, 0, 0.3, 0], three, [1, 0, 0.5, 1, 22, 16]
    yield "focal inside", W, H, full, RADIAL2, PAD, [17, 12, 0, 24, 16, 15], three, None
    yield "focal radius", W, H, full, RADIAL2, REFLECT, [20, 14, 3, 24, 16, 13], three, None
    yield "cone pad", W, H, full, RADIAL2, PAD, [9, 16, 4, 38, 15, 9], three, None
    yield "cone repeat", W, H, full, RADIAL2, REPEAT, [9, 16, 4, 38, 15, 9], two, None
    yield "cone reflect", W, H, full, RADIAL2, REFLECT, [12, 10, 2, 30, 22, 6], three, None
    yield "tangent (a = 0)", W, H, full, RADIAL2, PAD, [20, 16, 0, 30, 16, 10], three, None
    yield "concentric ring", W, H, full, RADIAL2, REPEAT, [24, 16, 5, 24, 16, 13], three, None
    yield "shrinking", W, H, full, RADIAL2, PAD, [16, 16, 14, 34, 14, 3], three, None
    yield "radial2 transformed", W, H, full, RADIAL2, PAD, [0, 0, 0, 4, 0, 10], three, rot
    yield "circle over bg", W, H, [('circle', 24, 16, 13.3)], LINEAR, PAD, [11, 0, 37, 0], [(0, 0xFFFF0000), (1, 0x8000FF00)], None
    yield "star over bg", W, H, [('star', 24, 16, 15, 6, 5, 0.2)], RADIAL, REPEAT, [24, 16, 5, 0], three, None
    for i in range(8):
        kind = rng.choice([LINEAR, RADIAL, CONIC, RADIAL2])
        n = rng.randint(1, 5)
        stops = sorted((round(rng.uniform(-0.1, 1.1), 3), rng.getrandbits(32)) for _ in range(n))
        if kind == LINEAR:
            geom = [rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0, W), rng.uniform(0, H)]
        elif kind == RADIAL:
            geom = [rng.uniform(0, W), rng.uniform(0, H), rng.uniform(2, 30), 0]
        elif kind == RADIAL2:
            geom = [rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0, 10),
                    rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0, 25)]
        else:
            geom = [rng.uniform(0, W), rng.uniform(0, H), rng.uniform(-7, 7), 0]
        shape = [('ellipse', rng.uniform(10, 38), rng.uniform(8, 24), rng.uniform(5, 20), rng.uniform(4, 14))]
        yield f"random {i}", W, H, shape, kind, rng.choice([PAD, REPEAT, REFLECT]), geom, stops, None


def main():
    tool = os.path.abspath(sys.argv[1])
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
    rng = random.Random(seed)
    bg = 0xFF305070
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_paint.") as d:
        for name, w, h, shape, kind, spread, geom, stops, matrix in gradient_cases(rng):
            total += 1
            cmds = shape + [('paint', kind, spread, geom, stops)]
            if matrix:
                cmds.append(('paint_transform', *matrix))
            got, rc = run_tool(tool, d, script(w, h, 0, cmds, None, 0.02, 0xFFFFFFFF, bg), w, h)
            cov, rc2 = run_tool(tool, d, script(w, h, 0, shape, None, 0.02, 0xFFFFFFFF, 0), w, h)
            if got is None or cov is None:
                print(f"FAIL  {name:20} exit {rc} {rc2}")
                failed += 1
                continue
            want = composite(colours(w, h, kind, spread, geom, stops, matrix), cov[..., 3], bg)
            want_px = np.stack([(want >> (8 * k)) & 255 for k in range(4)], axis=-1)
            diff = np.abs(got - want_px).max(axis=-1)
            off = int((diff > 1).sum())
            ok = off <= 3
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:20} max_diff={int(diff.max()):3d} pixels_off={off}")
        for name, shape, img, ex, ey, filt, matrix in image_cases(rng):
            total += 1
            w, h = 48, 32
            pixels = [int(p) for p in img.reshape(-1)]
            cmds = shape + [('image', img.shape[1], img.shape[0], ex, ey, filt, pixels)]
            if matrix:
                cmds.append(('paint_transform', *matrix))
            got, rc = run_tool(tool, d, script(w, h, 0, cmds, None, 0.02, 0xFFFFFFFF, bg), w, h)
            cov, rc2 = run_tool(tool, d, script(w, h, 0, shape, None, 0.02, 0xFFFFFFFF, 0), w, h)
            if got is None or cov is None:
                print(f"FAIL  {name:20} exit {rc} {rc2}")
                failed += 1
                continue
            want = composite(image_colours(w, h, img, ex, ey, filt, matrix), cov[..., 3], bg)
            want_px = np.stack([(want >> (8 * k)) & 255 for k in range(4)], axis=-1)
            diff = np.abs(got - want_px).max(axis=-1)
            off = int((diff > 1).sum())
            ok = off <= 3
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:20} max_diff={int(diff.max()):3d} pixels_off={off}")
        seg = [('rect', 0, 0, 8, 8)]
        two = [(0.0, 0xFFFF0000), (1.0, 0xFF0000FF)]
        for name, cmds in (("linear p0 = p1", [('paint', LINEAR, PAD, [3, 3, 3, 3], two)]),
                           ("radial r = 0", [('paint', RADIAL, PAD, [3, 3, 0, 0], two)]),
                           ("radial r < 0", [('paint', RADIAL, PAD, [3, 3, -2, 0], two)]),
                           ("no stops", [('paint', LINEAR, PAD, [0, 0, 8, 0], [])]),
                           ("nan offset", [('paint', LINEAR, PAD, [0, 0, 8, 0], [(math.nan, 0xFFFFFFFF)])]),
                           ("bad spread", [('paint', LINEAR, 3, [0, 0, 8, 0], two)]),
                           ("infinite geometry", [('paint', LINEAR, PAD, [0, 0, math.inf, 0], two)]),
                           ("radial2 r0 < 0", [('paint', RADIAL2, PAD, [3, 3, -1, 5, 5, 4], two)]),
                           ("radial2 same circle", [('paint', RADIAL2, PAD, [3, 3, 2, 3, 3, 2], two)]),
                           ("radial2 nan", [('paint', RADIAL2, PAD, [3, 3, 2, math.nan, 3, 2], two)]),
                           ("image bad extend", [('image', 2, 2, 4, 0, 0, [0xFF000000] * 4)]),
                           ("image bad filter", [('image', 2, 2, 0, 0, 2, [0xFF000000] * 4)]),
                           ("image zero size", [('image', 0, 2, 0, 0, 0, [])]),
                           ("singular transform", [('paint', LINEAR, PAD, [0, 0, 8, 0], two),
                                                   ('paint_transform', 1, 2, 2, 4, 0, 0)])):
            total += 1
            _, rc = run_tool(tool, d, script(8, 8, 0, seg + cmds), 8, 8)
            ok = rc == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  invalid {name:20} exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

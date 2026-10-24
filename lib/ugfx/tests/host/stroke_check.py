#!/usr/bin/env python3
"""Check ugfx strokes: widths, joins, caps, open and closed contours.

Usage: stroke_check.py <host_path binary> [--seed N]

The reference is the exact stroke region as a union of pieces: one
rectangle per segment, a join piece at every interior vertex (and every
vertex of a closed contour) on the outer side - miter quad within the
limit, else bevel triangle; round joins are the wedge between the two
offsets - and caps at the ends of
open contours (round: disks, square: half-width extensions, butt: none).
Its coverage is supersampled at 32x32 points per pixel, within about 1/32
of a pixel at each edge.

Where parts of a stroke overlap (a path crossing itself, tight curves),
ugfx's area rasterizer accumulates coverage inside an edge pixel instead of
taking the union (see raster_check.py and roadmap item C2D-027), so the
check is two-sided: ugfx must never be lighter than the exact union (lost
coverage is a geometry bug) and never darker than the sum of the pieces'
coverage, each within the sampling and flattening tolerance.

Development-machine tooling only; not part of any OS image.
"""
import math
import os
import random
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from path_check import Model, run_tool, script  # noqa: E402

SS = 32
JOINS = {'miter': 0, 'round': 1, 'bevel': 2}
CAPS = {'butt': 0, 'round': 1, 'square': 2}


def contours_with_flags(cmds):
    """Model.run, plus whether each contour was closed."""
    m = Model()
    closed = []
    for c in cmds:
        before = len(m.contours)
        was_open = m.open
        m.run([c])
        if len(m.contours) > before:
            closed.append(False)
        if c[0] == 'close' and was_open:
            closed[-1] = True
        if c[0] in ('rect', 'rrect', 'rrect4', 'ellipse', 'circle', 'pie', 'ring', 'polygon', 'star'):
            closed[-1] = True
    return m.contours, closed


def dedupe(pts, closed):
    out = []
    for p in pts:
        if not out or math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) > 1e-9:
            out.append(p)
    if closed and len(out) > 1 and math.hypot(out[-1][0] - out[0][0], out[-1][1] - out[0][1]) <= 1e-9:
        out.pop()
    return out


def pieces(pts, closed, h, join, cap, limit):
    pcs = []
    n = len(pts)
    if n == 1:
        (x, y), = pts
        if cap == 'round':
            pcs.append(('disk', x, y, h))
        elif cap == 'square':
            pcs.append(('poly', [(x - h, y - h), (x + h, y - h), (x + h, y + h), (x - h, y + h)]))
        return pcs
    segs = n if closed else n - 1

    def seg(i):
        a, b = pts[i % n], pts[(i + 1) % n]
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        d = ((b[0] - a[0]) / L, (b[1] - a[1]) / L)
        return a, b, d, (-d[1], d[0])

    for i in range(segs):
        a, b, d, nn = seg(i)
        pcs.append(('poly', [(a[0] + nn[0] * h, a[1] + nn[1] * h), (b[0] + nn[0] * h, b[1] + nn[1] * h),
                             (b[0] - nn[0] * h, b[1] - nn[1] * h), (a[0] - nn[0] * h, a[1] - nn[1] * h)]))
    verts = range(n) if closed else range(1, n - 1)
    for v in verts:
        _, p, dp, np_ = seg(v - 1)
        _, _, dc, nc = seg(v)
        cross = dp[0] * dc[1] - dp[1] * dc[0]
        dot = np_[0] * nc[0] + np_[1] * nc[1]
        if abs(cross) < 1e-12:
            if join == 'round' and dot < 0:
                pcs.append(('disk', p[0], p[1], h))     # a reversal: the half disk
            continue
        s = 1 if cross < 0 else -1          # the outer side
        o1 = (p[0] + s * h * np_[0], p[1] + s * h * np_[1])
        o2 = (p[0] + s * h * nc[0], p[1] + s * h * nc[1])
        if join == 'round':
            # the wedge between the two offsets (a disk would reach past
            # a butt end when the next segment is short)
            a0 = math.atan2(s * np_[1], s * np_[0])
            sweep = math.atan2(s * nc[1], s * nc[0]) - a0
            sweep = (sweep + math.pi) % math.tau - math.pi
            arc = [(p[0] + h * math.cos(a0 + sweep * i / 32), p[1] + h * math.sin(a0 + sweep * i / 32))
                   for i in range(33)]
            pcs.append(('poly', [p] + arc))
            continue
        if join == 'miter' and (1 + dot) / 2 * limit * limit >= 1:
            k = s * h / (1 + dot)
            mp = (p[0] + k * (np_[0] + nc[0]), p[1] + k * (np_[1] + nc[1]))
            pcs.append(('poly', [p, o1, mp, o2]))
        else:
            pcs.append(('poly', [p, o1, o2]))
    if not closed:
        for end, (a, b, d, nn), sgn in ((pts[-1], seg(segs - 1), 1), (pts[0], seg(0), -1)):
            if cap == 'round':
                # the half disk beyond the end (a whole disk would reach back
                # past a vertex when the last segment is shorter than h)
                a0 = math.atan2(nn[1], nn[0])
                turn = math.pi                  # the sweep whose middle points outward
                if math.cos(a0 + turn / 2) * d[0] * sgn + math.sin(a0 + turn / 2) * d[1] * sgn < 0:
                    turn = -turn
                arc = [(end[0] + h * math.cos(a0 + turn * i / 32), end[1] + h * math.sin(a0 + turn * i / 32))
                       for i in range(33)]
                pcs.append(('poly', arc))
            elif cap == 'square':
                dd = (d[0] * sgn * h, d[1] * sgn * h)
                pcs.append(('poly', [(end[0] + nn[0] * h, end[1] + nn[1] * h),
                                     (end[0] + nn[0] * h + dd[0], end[1] + nn[1] * h + dd[1]),
                                     (end[0] - nn[0] * h + dd[0], end[1] - nn[1] * h + dd[1]),
                                     (end[0] - nn[0] * h, end[1] - nn[1] * h)]))
    return pcs


def coverage(w, h, all_pieces):
    """(union coverage, summed coverage of the pieces) per pixel."""
    g = (np.arange(SS) + 0.5) / SS
    xs = (np.arange(w)[:, None] + g[None, :]).reshape(-1)
    ys = (np.arange(h)[:, None] + g[None, :]).reshape(-1)
    count = np.zeros((len(ys), len(xs)), np.int32)

    def window(x0, y0, x1, y1):
        """Sample index ranges covering the box (each piece is tested only there)."""
        c0, c1 = np.searchsorted(xs, x0), np.searchsorted(xs, x1, 'right')
        r0, r1 = np.searchsorted(ys, y0), np.searchsorted(ys, y1, 'right')
        return r0, r1, c0, c1

    for pc in all_pieces:
        if pc[0] == 'disk':
            _, cx, cy, r = pc
            r0, r1, c0, c1 = window(cx - r, cy - r, cx + r, cy + r)
            if r0 >= r1 or c0 >= c1:
                continue
            X, Y = np.meshgrid(xs[c0:c1], ys[r0:r1])
            count[r0:r1, c0:c1] += (X - cx) ** 2 + (Y - cy) ** 2 <= r * r
            continue
        poly = pc[1]
        area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
                   for i in range(len(poly)))
        if abs(area) < 1e-12:
            continue
        r0, r1, c0, c1 = window(min(p[0] for p in poly), min(p[1] for p in poly),
                                max(p[0] for p in poly), max(p[1] for p in poly))
        if r0 >= r1 or c0 >= c1:
            continue
        X, Y = np.meshgrid(xs[c0:c1], ys[r0:r1])
        sign = 1 if area > 0 else -1
        m = np.ones(X.shape, bool)
        for i in range(len(poly)):
            (x0, y0), (x1, y1) = poly[i], poly[(i + 1) % len(poly)]
            m &= sign * ((x1 - x0) * (Y - y0) - (y1 - y0) * (X - x0)) >= 0
        count[r0:r1, c0:c1] += m
    union = (count > 0).reshape(h, SS, w, SS).mean(axis=(1, 3))
    total = count.reshape(h, SS, w, SS).mean(axis=(1, 3))
    return union, total


def cases(rng):
    W, H = 56, 44
    zig = [('move', 6, 36), ('line', 18, 8), ('line', 30, 34), ('line', 42, 10), ('line', 50, 30)]
    for j in JOINS:
        for c in CAPS:
            yield f"zigzag {j}/{c}", W, H, zig, 4.5, 4.0, j, c
    yield "sharp miter limit", W, H, [('move', 4, 40), ('line', 28, 6), ('line', 52, 40)], 5, 10.0, 'miter', 'butt'
    yield "sharp miter beyond", W, H, [('move', 4, 40), ('line', 28, 6), ('line', 52, 40)], 5, 1.5, 'miter', 'butt'
    yield "closed square", W, H, [('move', 10, 10), ('line', 44, 10), ('line', 44, 34), ('line', 10, 34), ('close',)], 5, 4, 'miter', 'butt'
    yield "closed triangle round", W, H, [('polygon', [(8, 38), (28, 5), (48, 38)])], 6, 4, 'round', 'butt'
    yield "rect outline", W, H, [('rect', 8.5, 8.5, 38, 26)], 1, 4, 'miter', 'butt'
    yield "circle outline", W, H, [('circle', 28, 22, 15)], 3, 4, 'round', 'butt'
    yield "curve round caps", W, H, [('move', 6, 30), ('cubic', 16, -6, 40, 52, 50, 14)], 6, 4, 'round', 'round'
    yield "curve square caps", W, H, [('move', 6, 22), ('quad', 28, -10, 50, 22)], 4, 4, 'bevel', 'square'
    yield "u-turn", W, H, [('move', 10, 15), ('line', 45, 15), ('line', 10, 15.01)], 6, 4, 'round', 'butt'
    yield "dot round", W, H, [('move', 20, 20), ('line', 20, 20)], 10, 4, 'round', 'round'
    yield "dot square", W, H, [('move', 30.5, 20.5), ('close',)], 9, 4, 'miter', 'square'
    yield "dot butt", W, H, [('move', 30, 20)], 9, 4, 'miter', 'butt'
    yield "hairline width", W, H, [('move', 3, 3), ('line', 52, 41)], 0.5, 4, 'miter', 'butt'
    yield "thick", W, H, [('move', 14, 22), ('line', 42, 22)], 24, 4, 'miter', 'round'
    yield "star stroke", W, H, [('star', 28, 22, 18, 8, 5, 0.3)], 2.5, 4, 'miter', 'butt'
    for i in range(6):
        cmds = [('move', rng.uniform(4, 52), rng.uniform(4, 40))]
        for _ in range(rng.randint(2, 5)):
            cmds.append(('line', rng.uniform(4, 52), rng.uniform(4, 40)))
        if rng.random() < 0.4:
            cmds.append(('close',))
        yield (f"random {i}", W, H, cmds, rng.uniform(1, 7), rng.uniform(1, 6),
               rng.choice(list(JOINS)), rng.choice(list(CAPS)))


def main():
    tool = os.path.abspath(sys.argv[1])
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
    rng = random.Random(seed)
    tol = 0.01
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_stroke.") as d:
        for name, w, h, cmds, width, limit, join, cap in cases(rng):
            total += 1
            full = cmds + [('stroke', width, limit, JOINS[join], CAPS[cap])]
            got, rc = run_tool(tool, d, script(w, h, 0, full, None, tol), w, h)
            if got is None:
                print(f"FAIL  {name:24} exit {rc}")
                failed += 1
                continue
            contours, closed = contours_with_flags(cmds)
            pcs = []
            for pts, cl in zip(contours, closed):
                pts = dedupe(pts, cl)
                if pts:
                    pcs += pieces(pts, cl, width / 2, join, cap, limit)
            union, summed = coverage(w, h, pcs)
            low = np.minimum(np.floor(union * 256 + 1e-9), 255)
            high = np.minimum(np.floor(summed * 256 + 1e-9), 255)
            margin = 256 / SS + 2 + 256 * tol * 2
            a = got[..., 3]
            light = int((a < low - margin).sum())
            dark = int((a > high + margin).sum())
            ok = light == 0 and dark == 0
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:24} below_union={light} above_sum={dark} "
                  f"max_over_union={int((a - low).max()):3d}")
        for name, cmd in (("width zero", ('stroke', 0, 4, 0, 0)), ("bad join", ('stroke', 2, 4, 7, 0))):
            total += 1
            _, rc = run_tool(tool, d, script(16, 16, 0, [('move', 2, 2), ('line', 9, 9), cmd]), 16, 16)
            ok = rc == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  invalid {name:16} exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

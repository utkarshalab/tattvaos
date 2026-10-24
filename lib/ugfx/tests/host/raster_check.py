#!/usr/bin/env python3
"""Check ugfx's coverage rasterizer against an independent reference.

Usage: raster_check.py <host_raster binary> [--seed N] [--cases N]

The reference splits each pixel row into 256 sub-scanlines; on each one it
finds the exact edge crossings, walks them in order keeping the winding
number, and adds winding * covered length to each pixel. Per pixel the
accumulated value is then made absolute and clamped (nonzero) or folded
modulo 2 (even-odd). That is the coverage ugfx's area rasterizer is
specified to produce: exact for any pixel the shape covers once, and the
accumulated winding area where overlapping parts of the shape meet inside
one pixel (as in the classic area rasterizers). The reference is within
about 1/256 of that value, so ugfx (reported as min(floor(c * 256), 255))
must agree within a small tolerance.

Shapes: rectangles at fractional offsets, triangles, convex and concave
polygons, self-intersecting stars, holes with the same and opposite
winding, slivers, degenerate contours, shapes crossing every border and
far outside it, many contours, and both fill rules. Composite tests check
translucent colours over a non-empty background exactly.

Development-machine tooling only; not part of any OS image.
"""
import math
import os
import random
import struct
import subprocess
import sys
import tempfile

import numpy as np

SUB = 256          # reference sub-scanlines per pixel row
TOL = 3            # allowed difference in coverage levels


def div255(t):
    return (t + 128 + ((t + 128) >> 8)) >> 8


def reference_coverage(w, h, contours, rule):
    """contours: lists of (x, y) in pixel units (floats, already quantised)."""
    edges = []
    for pts in contours:
        n = len(pts)
        if n < 2:
            continue
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            if y0 != y1:
                edges.append((x0, y0, x1, y1))
    cov = np.zeros((h, w))
    if not edges:
        return cov
    e = np.array(edges)
    ex0, ey0, ex1, ey1 = e[:, 0], e[:, 1], e[:, 2], e[:, 3]
    ymin, ymax = np.minimum(ey0, ey1), np.maximum(ey0, ey1)
    direction = np.where(ey1 > ey0, 1, -1)
    for py in range(h):
        row = cov[py]
        for s in range(SUB):
            yy = py + (s + 0.5) / SUB
            act = (ymin <= yy) & (yy < ymax)
            if not act.any():
                continue
            xs = ex0[act] + (yy - ey0[act]) * (ex1[act] - ex0[act]) / (ey1[act] - ey0[act])
            ds = direction[act]
            order = np.argsort(xs, kind="stable")
            xs, ds = xs[order], ds[order]
            wind = 0
            for i in range(len(xs) - 1):
                wind += ds[i]
                if wind == 0:
                    continue
                a, b = max(xs[i], 0.0), min(xs[i + 1], float(w))
                if b <= a:
                    continue
                k = wind / SUB
                ia, ib = int(math.floor(a)), int(math.floor(b))
                if ia == ib:
                    row[ia] += (b - a) * k
                    continue
                row[ia] += (ia + 1 - a) * k
                if ib > ia + 1:
                    row[ia + 1:ib] += k
                if ib < w:
                    row[ib] += (b - ib) * k
    cov = np.abs(cov)
    if rule == 0:
        return np.minimum(cov, 1.0)
    cov = np.mod(cov, 2.0)
    return np.where(cov > 1.0, 2.0 - cov, cov)


def quantise(contours):
    """24.8 fixed point, as the rasterizer sees it."""
    q = [[(int(round(x * 256)), int(round(y * 256))) for x, y in c] for c in contours]
    return q, [[(x / 256, y / 256) for x, y in c] for c in q]


def write_shape(path, w, h, rule, color, bg, fixed):
    out = struct.pack("<6I", w, h, rule, color, bg, len(fixed))
    for c in fixed:
        out += struct.pack("<I", len(c))
        out += b"".join(struct.pack("<ii", x, y) for x, y in c)
    with open(path, "wb") as f:
        f.write(out)


def run(tool, d, w, h, rule, color, bg, fixed):
    shape, raw = os.path.join(d, "s.bin"), os.path.join(d, "o.raw")
    write_shape(shape, w, h, rule, color, bg, fixed)
    r = subprocess.run([tool, shape, raw], capture_output=True, timeout=60)
    if r.returncode:
        return None, f"exit {r.returncode}"
    px = np.frombuffer(open(raw, "rb").read(), np.uint8)
    if px.size != w * h * 4:
        return None, "short output"
    return px.reshape(h, w, 4).astype(np.int64), None


def star(cx, cy, r1, r2, n, rot=0.0):
    pts = []
    for i in range(2 * n):
        r = r1 if i % 2 == 0 else r2
        a = rot + math.pi * i / n
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def polygram(cx, cy, r, n, step, rot=0.0):
    return [(cx + r * math.cos(rot + 2 * math.pi * (i * step % n) / n),
             cy + r * math.sin(rot + 2 * math.pi * (i * step % n) / n)) for i in range(n)]


def rect(x, y, w, h, ccw=False):
    p = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    return p[::-1] if ccw else p


def cases(rng):
    W, H = 48, 40
    yield "unit pixel", W, H, [rect(10, 10, 1, 1)]
    yield "fractional rect", W, H, [rect(3.3, 4.7, 20.25, 11.6)]
    yield "subpixel rect", W, H, [rect(7.1, 7.2, 0.3, 0.45)]
    yield "triangle", W, H, [[(2.5, 3.1), (40.2, 12.7), (14.9, 37.3)]]
    yield "steep sliver", W, H, [[(20.0, 1.0), (20.4, 1.0), (21.1, 38.5)]]
    yield "flat sliver", W, H, [[(1.0, 20.0), (46.0, 20.3), (1.0, 20.5)]]
    yield "pentagram", W, H, [polygram(24, 20, 17, 5, 2, 0.3)]
    yield "star", W, H, [star(24, 20, 18, 7, 7, 0.1)]
    yield "hole opposite", W, H, [rect(4, 4, 36, 30), rect(12, 10, 18, 14, ccw=True)]
    yield "hole same", W, H, [rect(4, 4, 36, 30), rect(12, 10, 18, 14)]
    yield "overlap", W, H, [rect(5, 5, 20, 20), rect(15, 12, 22, 20)]
    yield "crossing borders", W, H, [[(-10.5, -6.2), (60.3, 8.8), (30.1, 55.7), (-4.4, 30.0)]]
    yield "far outside", W, H, [[(-5000, -3000), (9000.5, 20), (40.2, 7000.7)]]
    yield "left of clip", W, H, [rect(-30.5, 5.5, 50.2, 10.25)]
    yield "degenerate", W, H, [[(5, 5)], [(6, 6), (6, 6)], [(1, 1), (30, 30)], rect(8.5, 8.5, 9, 9)]
    for i in range(14):
        n = rng.randint(3, 12)
        pts = [(rng.uniform(-6, W + 6), rng.uniform(-6, H + 6)) for _ in range(n)]
        yield f"random polygon {i}", W, H, [pts]
    for i in range(6):
        cs = []
        for _ in range(rng.randint(2, 6)):
            cx, cy, r = rng.uniform(0, W), rng.uniform(0, H), rng.uniform(1, 14)
            cs.append(star(cx, cy, r, r * rng.uniform(0.3, 0.9), rng.randint(3, 9), rng.random()))
        yield f"many contours {i}", W, H, cs
    yield "large", 300, 220, [star(150, 110, 105, 40, 11, 0.2), rect(30.5, 20.25, 70, 60, ccw=True)]


def main():
    tool = os.path.abspath(sys.argv[1])
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
    rng = random.Random(seed)
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_raster.") as d:
        for name, w, h, contours in cases(rng):
            fixed, quant = quantise(contours)
            for rule in (0, 1):
                total += 1
                got, err = run(tool, d, w, h, rule, 0xFFFFFFFF, 0, fixed)
                cov = reference_coverage(w, h, quant, rule)
                if err:
                    print(f"FAIL  {name:20} {'nz' if rule == 0 else 'eo'}  {err}")
                    failed += 1
                    continue
                want = np.minimum(np.floor(cov * 256 + 1e-9), 255).astype(np.int64)
                diff = np.abs(got[..., 3] - want)
                bad = int((diff > TOL).sum())
                ok = bad == 0
                failed += not ok
                print(f"{'ok  ' if ok else 'FAIL'}  {name:20} {'nz' if rule == 0 else 'eo'}  "
                      f"maxdiff={int(diff.max())} over_tol={bad}")
        # compositing: translucent colour over a background, exact formula
        total += 1
        w, h = 32, 24
        fixed, quant = quantise([[(1.5, 2.25), (30.75, 5.5), (12.25, 22.5)]])
        bg = 0x80402010                      # premultiplied: a=128, r=64, g=32, b=16
        color = 0x99662211                   # a=153, r=102, g=34, b=17
        got, err = run(tool, d, w, h, 0, color, bg, fixed)
        cov = reference_coverage(w, h, quant, 0)
        want_a = np.minimum(np.floor(cov * 256 + 1e-9), 255).astype(np.int64)
        alpha = got[..., 3]
        # derive the coverage ugfx used from the alpha it produced, then check
        # every channel follows src-over exactly for that coverage
        errors = 0
        for y in range(h):
            for x in range(w):
                best = None
                for a in range(max(0, want_a[y, x] - TOL), min(255, want_a[y, x] + TOL) + 1):
                    s = [div255(((color >> (8 * k)) & 255) * a) for k in range(4)]
                    out = [s[k] + div255(((bg >> (8 * k)) & 255) * (255 - s[3])) for k in range(4)]
                    if a == 0:
                        out = [(bg >> (8 * k)) & 255 for k in range(4)]
                    if out == [int(v) for v in got[y, x]]:
                        best = a
                        break
                errors += best is None
        ok = err is None and errors == 0
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  {'composite':20} src-over exact, mismatched px={errors}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

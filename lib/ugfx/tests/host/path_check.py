#!/usr/bin/env python3
"""Check ugfx paths, shapes, transforms and flattening.

Usage: path_check.py <host_path binary> [--seed N]

Each case is a command script run through host_path and, in parallel,
through a Python model of the same path rules (implicit moves, close,
shape winding) built from exact geometry: true ellipses and densely
sampled Bezier curves. Both are rasterized by the coverage reference in
raster_check.py, so the only expected difference is flattening and the
cubic ellipse approximation: within (tolerance + 3e-4 * radius) pixels at
an edge, i.e. that many 1/256 coverage levels, plus a small margin.

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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from raster_check import reference_coverage  # noqa: E402

OPS = {'move': (0, 2), 'line': (1, 2), 'quad': (2, 4), 'cubic': (3, 6), 'close': (4, 0),
       'rect': (5, 4), 'rrect': (6, 5), 'rrect4': (7, 8), 'ellipse': (8, 4), 'circle': (9, 3),
       'arc': (10, 6), 'pie': (11, 6), 'ring': (12, 6), 'polygon': (13, None),
       'star': (14, 6), 'transform': (15, 6), 'stroke': (16, 4), 'dash': (17, None),
       'flatten': (18, 0), 'length': (19, 2), 'paint': (20, None), 'paint_transform': (21, 6),
       'image': (22, None)}
SAMPLES = 256        # reference points per curve or full turn


def script(w, h, rule, cmds, matrix=None, tol=0.02, color=0xFFFFFFFF, bg=0):
    out = struct.pack("<6I", w, h, rule, color, bg, 1 if matrix else 0)
    out += struct.pack("<7d", *(matrix or [1, 0, 0, 1, 0, 0]), tol)
    out += struct.pack("<Q", len(cmds))
    for name, *args in cmds:
        op, _ = OPS[name]
        out += struct.pack("<Q", op)
        if name == 'polygon':
            pts = args[0]
            out += struct.pack("<d", len(pts)) + b"".join(struct.pack("<2d", *p) for p in pts)
        elif name == 'paint':
            kind, spread, geom, stops = args
            geom = list(geom) + [0.0] * (6 - len(geom))
            out += struct.pack("<9d", kind, spread, *geom, len(stops))
            out += b"".join(struct.pack("<2d", o, c) for o, c in stops)
        elif name == 'image':
            w, h, ex, ey, filt, pixels = args
            out += struct.pack("<5d", w, h, ex, ey, filt)
            out += b"".join(struct.pack("<d", p) for p in pixels)
        elif name == 'dash':
            offset, intervals = args
            out += struct.pack(f"<2d{len(intervals)}d", offset, len(intervals), *intervals)
        else:
            out += struct.pack(f"<{len(args)}d", *args)
    return out


class Model:
    """Python mirror of ugfx path semantics, producing polygons."""

    def __init__(self):
        self.contours, self.cur, self.open, self.start = [], (0.0, 0.0), False, (0.0, 0.0)

    def move(self, x, y):
        if self.open and len(self.contours[-1]) == 1:
            self.contours[-1] = [(x, y)]
        else:
            self.contours.append([(x, y)])
        self.open, self.cur, self.start = True, (x, y), (x, y)

    def ensure(self):
        if not self.open:
            self.move(*self.cur)

    def line(self, x, y):
        self.ensure()
        self.contours[-1].append((x, y))
        self.cur = (x, y)

    def bez(self, pts):
        self.ensure()
        ctrl = [self.cur] + pts
        n = len(ctrl) - 1
        for s in range(1, SAMPLES + 1):
            t = s / SAMPLES
            self.contours[-1].append(tuple(sum(math.comb(n, i) * (1 - t) ** (n - i) * t ** i * ctrl[i][k]
                                               for i in range(n + 1)) for k in (0, 1)))
        self.cur = pts[-1]

    def close(self):
        if self.open:
            self.open, self.cur = False, self.start

    def arc(self, cx, cy, rx, ry, a0, sweep):
        sweep = max(-math.tau, min(math.tau, sweep))
        p0 = (cx + rx * math.cos(a0), cy + ry * math.sin(a0))
        (self.line if self.open else self.move)(*p0)
        if sweep == 0:
            return
        steps = max(4, int(SAMPLES * abs(sweep) / math.tau))
        for s in range(1, steps + 1):
            a = a0 + sweep * s / steps
            self.contours[-1].append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
        self.cur = self.contours[-1][-1]

    def run(self, cmds):
        for name, *a in cmds:
            if name == 'move':
                self.move(*a)
            elif name == 'line':
                self.line(*a)
            elif name == 'quad':
                self.bez([(a[0], a[1]), (a[2], a[3])])
            elif name == 'cubic':
                self.bez([(a[0], a[1]), (a[2], a[3]), (a[4], a[5])])
            elif name == 'close':
                self.close()
            elif name == 'rect':
                x, y, w, h = a
                self.move(x, y), self.line(x + w, y), self.line(x + w, y + h), self.line(x, y + h), self.close()
            elif name in ('rrect', 'rrect4'):
                x, y, w, h = a[:4]
                r = [max(v, 0.0) for v in (a[4:] if name == 'rrect4' else [a[4]] * 4)]
                sc = 1.0
                for s, side in ((r[0] + r[1], w), (r[3] + r[2], w), (r[0] + r[3], h), (r[1] + r[2], h)):
                    if s > 0:
                        sc = min(sc, side / s)
                r = [v * sc for v in r]
                self.move(x + r[0], y)
                for (ccx, ccy), rr, a0 in (((x + w - r[1], y + r[1]), r[1], -math.pi / 2),
                                           ((x + w - r[2], y + h - r[2]), r[2], 0.0),
                                           ((x + r[3], y + h - r[3]), r[3], math.pi / 2),
                                           ((x + r[0], y + r[0]), r[0], math.pi)):
                    if rr > 0:
                        self.arc(ccx, ccy, rr, rr, a0, math.pi / 2)
                    else:
                        self.line(ccx, ccy)
                self.close()
            elif name in ('ellipse', 'circle'):
                cx, cy, rx = a[:3]
                ry = a[3] if name == 'ellipse' else rx
                self.close()
                self.arc(cx, cy, rx, ry, 0.0, math.tau)
                self.close()
            elif name == 'arc':
                self.arc(*a)
            elif name == 'pie':
                cx, cy, rx, ry, a0, sw = a
                self.close(), self.move(cx, cy), self.arc(cx, cy, rx, ry, a0, sw), self.close()
            elif name == 'ring':
                cx, cy, ro, ri, a0, sw = a
                self.close()
                self.arc(cx, cy, ro, ro, a0, sw)
                if ri > 0:
                    sw = max(-math.tau, min(math.tau, sw))
                    self.arc(cx, cy, ri, ri, a0 + sw, -sw)
                else:
                    self.line(cx, cy)
                self.close()
            elif name == 'polygon':
                pts = a[0]
                self.close(), self.move(*pts[0])
                for p in pts[1:]:
                    self.line(*p)
                self.close()
            elif name == 'star':
                cx, cy, ro, ri, tips, rot = a
                self.close()
                n = 2 * int(tips)
                for i in range(n):
                    rr = ro if i % 2 == 0 else ri
                    ang = rot + i * math.tau / n
                    p = (cx + rr * math.cos(ang), cy + rr * math.sin(ang))
                    (self.move if i == 0 else self.line)(*p)
                self.close()
            elif name == 'transform':
                m = a
                self.contours = [[(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]) for x, y in c]
                                 for c in self.contours]
                self.cur = (m[0] * self.cur[0] + m[2] * self.cur[1] + m[4],
                            m[1] * self.cur[0] + m[3] * self.cur[1] + m[5])
        return self.contours


def run_tool(tool, d, data, w, h):
    sp, raw = os.path.join(d, "p.bin"), os.path.join(d, "o.raw")
    with open(sp, "wb") as f:
        f.write(data)
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    if r.returncode:
        return None, r.returncode
    px = np.frombuffer(open(raw, "rb").read(), np.uint8)
    return px.reshape(h, w, 4).astype(np.int64), 0


def cases(rng):
    W, H = 64, 48
    yield "rect", W, H, [('rect', 5.25, 6.5, 40.3, 20.7)], None, 0.02, 0
    yield "lines", W, H, [('move', 3, 3), ('line', 60, 10.5), ('line', 30.2, 44.4), ('close',)], None, 0.02, 0
    yield "implicit move", W, H, [('line', 50, 5), ('line', 40, 40)], None, 0.02, 0
    yield "quad", W, H, [('move', 4, 40), ('quad', 32, -20, 60, 40), ('close',)], None, 0.02, 0
    yield "cubic", W, H, [('move', 4, 24), ('cubic', 10, -10, 54, 58, 60, 24), ('line', 30, 46)], None, 0.02, 0
    yield "loop cubic", W, H, [('move', 10, 40), ('cubic', 70, -10, -10, -10, 50, 40)], None, 0.02, 0
    yield "rounded rect", W, H, [('rrect', 4.5, 4.5, 55, 39, 9.5)], None, 0.02, 0
    yield "rounded rect clamp", W, H, [('rrect', 8, 8, 30, 20, 50)], None, 0.02, 0
    yield "rounded rect radii", W, H, [('rrect4', 3, 3, 58, 42, 0, 6, 18, 2.5)], None, 0.02, 0
    yield "ellipse", W, H, [('ellipse', 32, 24, 27.5, 18.25)], None, 0.02, 0
    yield "circle", W, H, [('circle', 31.6, 23.2, 15.7)], None, 0.02, 0
    yield "arc chord", W, H, [('arc', 32, 24, 20, 14, 0.3, 4.0), ('close',)], None, 0.02, 0
    yield "arc after line", W, H, [('move', 2, 2), ('arc', 40, 30, 15, 15, -1.0, -2.5)], None, 0.02, 0
    yield "pie", W, H, [('pie', 30, 25, 22, 20, -0.5, 2.2)], None, 0.02, 0
    yield "pie reverse", W, H, [('pie', 30, 25, 22, 20, 1.0, -4.5)], None, 0.02, 0
    yield "ring sector", W, H, [('ring', 32, 24, 22, 12, 0.4, 3.9)], None, 0.02, 0
    yield "full ring", W, H, [('ring', 32, 24, 21, 10, 0.0, math.tau)], None, 0.02, 0
    yield "polygon", W, H, [('polygon', [(5, 5), (58, 9), (40, 44), (12, 30)])], None, 0.02, 0
    yield "star", W, H, [('star', 32, 24, 22, 9, 5, 0.2)], None, 0.02, 0
    yield "donut evenodd", W, H, [('circle', 32, 24, 20), ('circle', 32, 24, 10)], None, 0.02, 1
    yield "matrix rotate scale", W, H, [('rrect', -10, -6, 20, 12, 3)], \
        [1.8 * math.cos(0.6), 1.8 * math.sin(0.6), -1.2 * math.sin(0.6), 1.2 * math.cos(0.6), 32, 24], 0.02, 0
    yield "matrix skew", W, H, [('ellipse', 20, 20, 12, 8)], [1, 0.1, 0.6, 1.05, 2.5, 1.25], 0.02, 0
    yield "path transform op", W, H, [('circle', 0, 0, 10), ('transform', 2, 0, 0, 1, 30, 24)], None, 0.02, 0
    yield "coarse tolerance", W, H, [("circle", 32, 24, 20)], None, 0.25, 0
    yield "offscreen curves", W, H, [('ellipse', 0, 0, 90, 70), ('cubic', 300, -50, -400, 90, 63, 47)], None, 0.02, 0
    yield "large", 320, 240, [('rrect', 10.5, 10.5, 300, 220, 40), ('star', 160, 120, 100, 40, 12, 0.1)], None, 0.05, 1
    for i in range(10):
        cmds = [('move', rng.uniform(0, 64), rng.uniform(0, 48))]
        for _ in range(rng.randint(2, 6)):
            k = rng.choice(['line', 'quad', 'cubic'])
            n = {'line': 2, 'quad': 4, 'cubic': 6}[k]
            cmds.append((k, *[rng.uniform(-10, 74) if j % 2 == 0 else rng.uniform(-10, 58) for j in range(n)]))
        yield f"random curves {i}", W, H, cmds, None, rng.choice([0.01, 0.05, 0.25]), rng.randint(0, 1)


def errors(tool, d):
    bad = [('rect', 0, 0, -1, 5), ('rect', 0, 0, math.nan, 5), ('ellipse', 1, 1, 0, 3), ('star', 5, 5, 3, 2, 1, 0),
           ('ring', 10, 10, 5, 6, 0, 1), ('polygon', [(1, 1)])]
    failed = 0
    for cmd in bad:
        _, rc = run_tool(tool, d, script(16, 16, 0, [cmd]), 16, 16)
        ok = rc == 5
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  invalid {cmd[0]:16} exit={rc}")
    return failed, len(bad)


def main():
    tool = os.path.abspath(sys.argv[1])
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
    rng = random.Random(seed)
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_path.") as d:
        for name, w, h, cmds, matrix, tol, rule in cases(rng):
            total += 1
            got, rc = run_tool(tool, d, script(w, h, rule, cmds, matrix, tol), w, h)
            if got is None:
                print(f"FAIL  {name:22} exit {rc}")
                failed += 1
                continue
            polys = Model().run(cmds)
            if matrix:
                a, b, c, e_, f_, g_ = matrix
                polys = [[(a * x + c * y + f_, b * x + e_ * y + g_) for x, y in p] for p in polys]
            want = np.minimum(np.floor(reference_coverage(w, h, polys, rule) * 256 + 1e-9), 255)
            radius = max((abs(v) for c in cmds for v in c[1:] if isinstance(v, float)), default=0)
            scale = max((abs(v) for v in (matrix or [1])[:4]), default=1)
            limit = 4 + 256 * (tol + 3e-4 * min(radius, 100) * scale)
            diff = np.abs(got[..., 3] - want)
            ok = diff.max() <= limit
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:22} maxdiff={int(diff.max()):3d} limit={limit:.0f}")
        f, n = errors(tool, d)
        failed += f
        total += n
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

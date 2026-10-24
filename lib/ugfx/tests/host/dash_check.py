#!/usr/bin/env python3
"""Check ugfx dashes, flattening and path length.

Usage: dash_check.py <host_path binary> [--seed N]

Dashes: each case dashes a path, strokes the dashes and compares with a
reference built from the same pieces as stroke_check.py. The reference
dashing is done over arc length: every contour gets the pattern laid out
from its start as distance ranges (on runs; a run ends at a vertex or
crosses it), a closed contour that starts and ends inside a dash joins
those two runs, and a contour entirely inside one dash stays closed. The
check is the same two-sided bound as stroke_check.py.

Flattening: a path filled as is and filled after ugfx_path_flatten must
match within the flattening tolerance.

Length: ugfx_path_length of lines, closed polygons and curves against the
exact (or finely integrated) length.

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
from stroke_check import CAPS, JOINS, contours_with_flags, coverage, dedupe, pieces  # noqa: E402

SS = 32


def dash_ranges(L, closed, intervals, offset):
    """On runs of one contour of length L as (start, end) distances; a
    closed contour's joined run may end past L (it wraps). None = whole."""
    pat = list(intervals) * (2 if len(intervals) % 2 else 1)
    period = sum(pat)
    phase = math.fmod(offset, period)
    if phase < 0:
        phase += period
    if phase >= period:
        phase = 0.0
    k = 0
    while phase >= pat[k]:
        phase -= pat[k]
        k += 1
        if k == len(pat):
            k, phase = 0, 0.0
            break
    runs, pos, rem = [], 0.0, pat[k] - phase
    start_on = k % 2 == 0
    while True:
        on = k % 2 == 0
        end = pos + rem
        if L - pos <= rem:
            if on:
                runs.append((pos, L))
            break
        if on:
            runs.append((pos, end))
        pos = end
        k = (k + 1) % len(pat)
        rem = pat[k]
    if closed and start_on:
        if len(runs) == 1 and runs[0] == (0.0, L):
            return None
        first = runs.pop(0)
        if runs and runs[-1][1] >= L and runs[-1][0] < L:
            last = runs.pop()
            runs.append((last[0], L + first[1]))
        else:
            runs.append((L, L + first[1]))
    return runs


def polyline_range(pts, closed, a, b):
    """Points of the contour between distances a and b (b may wrap once)."""
    seq = pts + [pts[0]] + pts[1:] + [pts[0]] if closed else pts
    cum = [0.0]
    for p, q in zip(seq, seq[1:]):
        cum.append(cum[-1] + math.hypot(q[0] - p[0], q[1] - p[1]))

    def at(d):
        for i in range(len(seq) - 1):
            if d <= cum[i + 1] or i == len(seq) - 2:
                seg = cum[i + 1] - cum[i]
                t = 0.0 if seg <= 0 else (d - cum[i]) / seg
                p, q = seq[i], seq[i + 1]
                return (p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t)

    out = [at(a)]
    for i in range(1, len(seq)):
        if a < cum[i] < b:
            out.append(seq[i])
    out.append(at(b))
    return out


def dash_pieces(cmds, intervals, offset, width, limit, join, cap):
    contours, closed = contours_with_flags(cmds)
    pcs = []
    for pts, cl in zip(contours, closed):
        pts = dedupe(pts, cl)
        if len(pts) < 2:
            continue
        L = sum(math.hypot(q[0] - p[0], q[1] - p[1]) for p, q in zip(pts, pts[1:] + (pts[:1] if cl else [])))
        runs = dash_ranges(L, cl, intervals, offset)
        if runs is None:
            pcs += pieces(pts, True, width / 2, join, cap, limit)
            continue
        for a, b in runs:
            line = dedupe(polyline_range(pts, cl, a, b), False)
            pcs += pieces(line, False, width / 2, join, cap, limit)
    return pcs


def dash_cases(rng):
    W, H = 64, 40
    line = [('move', 4, 20), ('line', 60, 20)]
    zig = [('move', 4, 34), ('line', 18, 6), ('line', 32, 32), ('line', 46, 8), ('line', 60, 30)]
    sq = [('move', 10, 8), ('line', 54, 8), ('line', 54, 32), ('line', 10, 32), ('close',)]
    yield "line 6/4", W, H, line, [6, 4], 0, 4, 4, 'miter', 'butt'
    yield "line offset", W, H, line, [6, 4], 3, 4, 4, 'miter', 'butt'
    yield "line negative offset", W, H, line, [6, 4], -2.5, 4, 4, 'miter', 'butt'
    yield "line big offset", W, H, line, [6, 4], 1e6 + 1.5, 4, 4, 'miter', 'butt'
    yield "odd pattern", W, H, line, [5], 0, 4, 4, 'miter', 'square'
    yield "three intervals", W, H, line, [7, 2, 1], 0.5, 3, 4, 'miter', 'round'
    yield "zigzag miter", W, H, zig, [14, 5], 0, 4, 4, 'miter', 'butt'
    yield "zigzag round", W, H, zig, [9, 6], 2, 5, 4, 'round', 'round'
    yield "zigzag bevel", W, H, zig, [20, 3], 8, 4, 4, 'bevel', 'square'
    yield "square closed join", W, H, sq, [20, 6], 0, 4, 4, 'miter', 'butt'
    yield "square closed off start", W, H, sq, [20, 6], 23, 4, 4, 'miter', 'butt'
    yield "square ends on", W, H, sq, [17, 3], 0, 4, 4, 'round', 'round'
    yield "square whole", W, H, sq, [1000, 5], 0, 4, 4, 'miter', 'butt'
    yield "rect", W, H, [('rect', 8.5, 6.5, 46, 26)], [8, 4], 0, 2, 4, 'miter', 'butt'
    yield "circle", W, H, [('circle', 32, 20, 15)], [6, 4], 0, 3, 4, 'miter', 'butt'
    yield "circle round", W, H, [('circle', 32, 20, 14)], [1, 5], 0, 4, 4, 'round', 'round'
    yield "cubic", W, H, [('move', 4, 30), ('cubic', 16, -8, 46, 50, 60, 10)], [8, 5], 1, 3, 4, 'round', 'butt'
    yield "quad", W, H, [('move', 4, 34), ('quad', 32, -20, 60, 34)], [5, 3], 0, 2.5, 4, 'miter', 'square'
    yield "dots round", W, H, line, [0, 7], 0, 5, 4, 'miter', 'round'
    yield "dots square", W, H, line, [0, 8], 2, 4, 4, 'miter', 'square'
    yield "dots butt vanish", W, H, line, [0, 8], 0, 4, 4, 'miter', 'butt'
    yield "two contours restart", W, H, [('move', 4, 10), ('line', 60, 10), ('move', 4, 30), ('line', 60, 30)], [9, 5], 4, 3, 4, 'miter', 'butt'
    yield "star", W, H, [('star', 32, 20, 18, 8, 5, 0.2)], [7, 4], 0, 2, 4, 'miter', 'butt'
    for i in range(6):
        cmds = [('move', rng.uniform(4, 60), rng.uniform(4, 36))]
        for _ in range(rng.randint(2, 5)):
            cmds.append(('line', rng.uniform(4, 60), rng.uniform(4, 36)))
        if rng.random() < 0.4:
            cmds.append(('close',))
        pat = [round(rng.uniform(0.5, 12), 2) for _ in range(rng.choice([1, 2, 2, 3, 4]))]
        yield (f"random {i}", W, H, cmds, pat, round(rng.uniform(-20, 20), 2), rng.uniform(1, 5), rng.uniform(1, 5),
               rng.choice(list(JOINS)), rng.choice(list(CAPS)))


def check_dashes(tool, d, rng, tol):
    failed = total = 0
    for name, w, h, cmds, pat, offset, width, limit, join, cap in dash_cases(rng):
        total += 1
        full = cmds + [('dash', offset, pat), ('stroke', width, limit, JOINS[join], CAPS[cap])]
        got, rc = run_tool(tool, d, script(w, h, 0, full, None, tol), w, h)
        if got is None:
            print(f"FAIL  dash {name:24} exit {rc}")
            failed += 1
            continue
        union, summed = coverage(w, h, dash_pieces(cmds, pat, offset, width, limit, join, cap))
        low = np.minimum(np.floor(union * 256 + 1e-9), 255)
        high = np.minimum(np.floor(summed * 256 + 1e-9), 255)
        margin = 256 / SS + 2 + 256 * tol * 4
        a = got[..., 3]
        light = int((a < low - margin).sum())
        dark = int((a > high + margin).sum())
        ok = light == 0 and dark == 0
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  dash {name:24} below_union={light} above_sum={dark}")
    seg = [('move', 2, 2), ('line', 12, 12)]
    for name, pat in (("no intervals", []), ("negative", [4, -1]), ("all zero", [0, 0]),
                      ("infinite", [math.inf, 2]), ("nan", [math.nan])):
        total += 1
        _, rc = run_tool(tool, d, script(16, 16, 0, seg + [('dash', 0, pat)]), 16, 16)
        ok = rc == 5
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  dash invalid {name:16} exit={rc}")
    total += 1
    _, rc = run_tool(tool, d, script(16, 16, 0, seg + [('dash', math.inf, [2, 2])]), 16, 16)
    failed += rc != 5
    print(f"{'ok  ' if rc == 5 else 'FAIL'}  dash invalid {'infinite offset':16} exit={rc}")
    return failed, total


def check_flatten(tool, d, tol):
    failed = total = 0
    W, H = 64, 48
    for name, cmds in (("quad", [('move', 4, 40), ('quad', 32, -20, 60, 40), ('close',)]),
                       ("cubic loop", [('move', 10, 40), ('cubic', 70, -10, -10, -10, 50, 40)]),
                       ("circle + rect", [('circle', 30, 24, 16), ('rect', 40, 4, 20, 20)]),
                       ("rounded rect", [('rrect', 4.5, 4.5, 55, 39, 9.5)]),
                       ("lines only", [('move', 3, 3), ('line', 60, 10.5), ('line', 30.2, 44.4), ('close',)])):
        total += 1
        ref, rc1 = run_tool(tool, d, script(W, H, 0, cmds, None, tol), W, H)
        got, rc2 = run_tool(tool, d, script(W, H, 0, cmds + [('flatten',)], None, tol), W, H)
        if ref is None or got is None:
            print(f"FAIL  flatten {name:20} exit {rc1} {rc2}")
            failed += 1
            continue
        diff = int(np.abs(ref[..., 3] - got[..., 3]).max())
        ok = diff <= 256 * tol * 2 + 2
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  flatten {name:20} max_diff={diff}")
    return failed, total


def bezier_length(ctrl, n=20000):
    def pt(t):
        m = len(ctrl) - 1
        x = y = 0.0
        for i, (px, py) in enumerate(ctrl):
            b = math.comb(m, i) * t ** i * (1 - t) ** (m - i)
            x, y = x + b * px, y + b * py
        return x, y
    total, prev = 0.0, pt(0)
    for i in range(1, n + 1):
        cur = pt(i / n)
        total += math.hypot(cur[0] - prev[0], cur[1] - prev[1])
        prev = cur
    return total


def check_length(tool, d, tol):
    failed = total = 0
    cubic = [(4, 24), (10, -10), (54, 58), (60, 24)]
    quad = [(4, 40), (32, -20), (60, 40)]
    for name, cmds, expected in (
            ("empty", [], 0.0),
            ("line 3-4-5", [('move', 1, 1), ('line', 4, 5)], 5.0),
            ("open polyline", [('move', 0, 0), ('line', 10, 0), ('line', 10, 10)], 20.0),
            ("closed triangle", [('move', 0, 0), ('line', 3, 0), ('line', 3, 4), ('close',)], 12.0),
            ("rect", [('rect', 2, 3, 10, 5)], 30.0),
            ("two contours", [('rect', 0, 0, 1, 1), ('move', 5, 5), ('line', 5, 9)], 8.0),
            ("circle", [('circle', 20, 20, 15)], 2 * math.pi * 15),
            ("quad", [('move', *quad[0]), ('quad', *quad[1], *quad[2])], bezier_length(quad)),
            ("cubic", [('move', *cubic[0]), ('cubic', *cubic[1], *cubic[2], *cubic[3])], bezier_length(cubic))):
        total += 1
        err = 1e-9 + 2e-3 * expected
        _, rc = run_tool(tool, d, script(8, 8, 0, cmds + [('length', expected, err)], None, tol), 8, 8)
        _, rc_off = run_tool(tool, d, script(8, 8, 0, cmds + [('length', expected + 1, err)], None, tol), 8, 8)
        ok = rc == 0 and rc_off == 5
        failed += not ok
        print(f"{'ok  ' if ok else 'FAIL'}  length {name:20} expected={expected:.4f} exit={rc}/{rc_off}")
    return failed, total


def main():
    tool = os.path.abspath(sys.argv[1])
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
    rng = random.Random(seed)
    tol = 0.01
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_dash.") as d:
        for f, t in (check_dashes(tool, d, rng, tol), check_flatten(tool, d, 0.02), check_length(tool, d, tol)):
            failed += f
            total += t
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check ugfx's lines and discs pixel for pixel (G2D-01).

Usage: prims_check.py <host_prims binary> [--seed N] [--cases N]

The reference draws as 2d/line.asm and 2d/circle.asm say they do: the
all-octant Bresenham line, both ends included, pixels off the buffer
skipped; the filled ellipse of every pixel with
ry^2 x^2 + rx^2 y^2 <= rx^2 ry^2 + rx ry (rx + ry) / 2 (a circle is the
ellipse with rx = ry). Cases: every octant and the axes, single points,
lines and discs half or wholly off the buffer, far outside it, radius 0,
flat ellipses, and out-of-range arguments, which must change nothing and
return -EINVAL. Every pixel must match.

Development-machine tooling only; not part of any OS image.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

EINVAL = 22
LIMIT = 32767


def line(px, w, h, x0, y0, x1, y1, c):
    if any(abs(v) > LIMIT for v in (x0, y0, x1, y1)):
        return -EINVAL
    dx, sx = abs(x1 - x0), (1 if x0 < x1 else -1)
    dy, sy = -abs(y1 - y0), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        if 0 <= x0 < w and 0 <= y0 < h:
            px[y0 * w + x0] = c
        if x0 == x1 and y0 == y1:
            return 0
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def ellipse(px, w, h, cx, cy, rx, ry, c):
    if abs(cx) > LIMIT or abs(cy) > LIMIT or not 0 <= rx <= LIMIT or not 0 <= ry <= LIMIT:
        return -EINVAL
    a2, b2 = rx * rx, ry * ry
    r = a2 * b2 + rx * ry * (rx + ry) // 2
    for y in range(-ry, ry + 1):
        row = cy + y
        if not 0 <= row < h:
            continue
        t = r - a2 * y * y
        if b2 == 0:
            half = rx
        else:
            half = 0
            while b2 * (half + 1) ** 2 <= t:
                half += 1
        for x in range(max(cx - half, 0), min(cx + half, w - 1) + 1):
            px[row * w + x] = c
    return 0


def cases(rng, n):
    out = []
    for dx, dy in [(5, 0), (-5, 0), (0, 5), (0, -5), (6, 2), (2, 6), (-6, 2), (-2, 6),
                   (6, -2), (2, -6), (-6, -2), (-2, -6), (4, 4), (-4, 4), (0, 0)]:
        out.append((1, 20, 15, 20 + dx, 15 + dy))
    out += [(1, -10, -10, 50, 40), (1, -1000, 5, 1000, 25), (1, 3, -5000, 3, 5000),
            (1, -30000, -30000, 30000, 30000), (1, 40000, 0, 0, 0), (1, 0, 0, 0, -40000),
            (2, 20, 15, 0), (2, 20, 15, 1), (2, 20, 15, 7), (2, 0, 0, 10), (2, 39, 29, 12),
            (2, -100, 15, 103), (2, 20, 15, -1), (2, 20, 15, 40000), (2, 50000, 0, 3),
            (3, 20, 15, 9, 0), (3, 20, 15, 0, 6), (3, 20, 15, 12, 4), (3, 20, 15, 3, 11),
            (3, -5, -5, 20, 20), (3, 20, 15, -2, 3),
            # huge discs whose edge crosses the buffer: there the square root
            # of numbers near 10^18 must be made exact
            (2, 20, 32700, 32690), (2, -32700, 15, 32715), (2, 32760, 32760, 32767),
            (3, 20, 32000, 30000, 31990), (3, -31000, 15, 31020, 32767),
            (3, 32767, -32767, 32767, 32767)]
    for _ in range(n):
        k = rng.choice((1, 2, 3))
        if k == 1:
            out.append((1, rng.randint(-20, 60), rng.randint(-20, 50),
                        rng.randint(-20, 60), rng.randint(-20, 50)))
        elif k == 2:
            out.append((2, rng.randint(-10, 50), rng.randint(-10, 40), rng.randint(0, 30)))
        else:
            out.append((3, rng.randint(-10, 50), rng.randint(-10, 40),
                        rng.randint(0, 30), rng.randint(0, 30)))
    return out


def run(tool, w, h, bg, cmds):
    with tempfile.TemporaryDirectory(prefix='ugfx_prims.') as d:
        cmd_path, out_path = os.path.join(d, 'cmds'), os.path.join(d, 'out')
        b = struct.pack('<4I', w, h, bg, len(cmds))
        for kind, *args in cmds:
            args = [v - (1 << 32) if v >= (1 << 31) else v for v in args] + [0] * (6 - len(args))
            b += struct.pack('<I6i', kind, *args)
        open(cmd_path, 'wb').write(b)
        r = subprocess.run([tool, cmd_path, out_path], capture_output=True)
        if r.returncode:
            raise SystemExit(f'prims_check: host_prims exited {r.returncode}')
        data = open(out_path, 'rb').read()
    pixels = list(struct.unpack(f'<{w * h}I', data[:w * h * 4]))
    results = list(struct.unpack(f'<{len(cmds)}i', data[w * h * 4:]))
    return pixels, results


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    tool = sys.argv[1]
    seed = int(sys.argv[sys.argv.index('--seed') + 1]) if '--seed' in sys.argv else 1
    n = int(sys.argv[sys.argv.index('--cases') + 1]) if '--cases' in sys.argv else 300
    rng = random.Random(seed)
    w, h, bg = 41, 31, 0xFF101010
    failures = 0
    for i, (kind, *args) in enumerate(cases(rng, n)):
        colour = 0xFF000000 | (i * 2654435761 & 0xFFFFFF)
        want = [bg] * (w * h)
        if kind == 1:
            expect = line(want, w, h, *args, colour)
        elif kind == 2:
            expect = ellipse(want, w, h, args[0], args[1], args[2], args[2], colour)
        else:
            expect = ellipse(want, w, h, *args, colour)
        got, results = run(tool, w, h, bg, [(kind, *args, colour)])
        bad = sum(1 for a, b in zip(got, want) if a != b)
        if bad or results[0] != expect:
            failures += 1
            print(f'FAIL  {["", "line", "circle", "ellipse"][kind]} {args}: '
                  f'{bad} pixels differ, returned {results[0]} (want {expect})')
    total = len(cases(random.Random(seed), n))
    print(f'prims_check: {total - failures}/{total} passed')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Check the ugfx drawing context: state, save/restore, transforms, paints in
user space, strokes and dashes, clips, global alpha, fill rules, rects,
images, clear and layers.

Usage: ctx_check.py <host_ctx binary> <host_path binary>

The reference is a small context in Python built from pieces the other
checks verify on their own: every coverage comes from host_path (the same
path, matrix, tolerance and rule, rendered solid white over transparent),
colours from the paint and image models of paint_check.py, clips and alpha
as exact x / 255 products (alpha first, then the clip, as the rasterizer
applies them), compositing source-over with ugfx's rounding onto the
current target. Matrices are multiplied and inverted with umath's formulas.
So this checks the context's own work: which state each call uses, how
save/restore, clips and layers move it, and in what order things happen.
Each channel must match within 1 (umath's sin/cos may differ from
Python's in the last bit), on all but 3 pixels.

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
import paint_check  # noqa: E402
from path_check import OPS, run_tool, script  # noqa: E402
from paint_check import (LINEAR, RADIAL, CONIC, PAD, REPEAT, REFLECT, BILINEAR,  # noqa: E402
                         colours, composite, div255, image_colours, random_image)

W, H = 48, 32
BG = 0xFF305070
DEFAULT_TOL = 0.1


def mul(m1, m2):
    """umath_affine2_multiply: apply m2, then m1."""
    a1, b1, c1, d1, e1, f1 = m1
    a2, b2, c2, d2, e2, f2 = m2
    return [a1 * a2 + c1 * b2, b1 * a2 + d1 * b2, a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
            a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1]


def invert(m):
    """umath_affine2_invert."""
    a, b, c, d, e, f = m
    inv = 1.0 / (a * d - b * c)
    return [d * inv, -b * inv, -c * inv, a * inv, (c * f - d * e) * inv, (b * e - a * f) * inv]


paint_check.invert = invert             # the paint models place paints the same way

CTX_OPS = {'new_path': (30, 0), 'fill': (31, 0), 'stroke': (32, 0), 'clip': (33, 0), 'save': (34, 0),
           'restore': (35, 0), 'set_transform': (36, 6), 'transform': (37, 6), 'translate': (38, 2),
           'scale': (39, 2), 'rotate': (40, 1), 'fill_color': (41, 1), 'stroke_color': (42, 1),
           'fill_gradient': (43, None), 'stroke_gradient': (44, None), 'stroke_style': (45, 4),
           'dash': (46, None), 'alpha': (47, 1), 'rule': (48, 1), 'tolerance': (49, 1),
           'fill_rect': (50, 4), 'stroke_rect': (51, 4), 'draw_image': (52, None), 'clear': (53, 1),
           'begin_layer': (54, 1), 'end_layer': (55, 0)}
PATH_OPS = ('move', 'line', 'quad', 'cubic', 'close', 'rect', 'ellipse', 'circle')


def encode(cmds):
    out = struct.pack("<4I", W, H, BG, 0) + struct.pack("<Q", len(cmds))
    for name, *a in cmds:
        if name in PATH_OPS:
            out += struct.pack("<Q", OPS[name][0]) + struct.pack(f"<{len(a)}d", *a)
            continue
        op, _ = CTX_OPS[name]
        out += struct.pack("<Q", op)
        if name in ('fill_gradient', 'stroke_gradient'):
            kind, spread, geom, stops, m = a
            geom = list(geom) + [0.0] * (6 - len(geom))
            out += struct.pack("<9d", kind, spread, *geom, len(stops))
            out += b"".join(struct.pack("<2d", o, c) for o, c in stops) + struct.pack("<6d", *m)
        elif name == 'dash':
            off, iv = a
            out += struct.pack(f"<2d{len(iv)}d", off, len(iv), *iv)
        elif name == 'draw_image':
            x, y, w, h, img = a
            out += struct.pack("<6d", x, y, w, h, img.shape[1], img.shape[0])
            out += b"".join(struct.pack("<d", int(p)) for p in img.reshape(-1))
        else:
            out += struct.pack(f"<{len(a)}d", *a)
    return out


class Ref:
    def __init__(self, path_tool, d):
        self.tool, self.d = path_tool, d
        self.bufs = [np.full((H, W), BG, np.int64)]     # buffers by id: the root, then layers
        self.st = dict(T=[1.0, 0, 0, 1.0, 0, 0], tol=DEFAULT_TOL, clip=None, rule=0, alpha=255, target=0,
                       fill=('solid', 0xFF000000, [1.0, 0, 0, 1.0, 0, 0]),
                       stroke=('solid', 0xFF000000, [1.0, 0, 0, 1.0, 0, 0]),
                       style=(1.0, 10.0, 0, 0), dash=None, layer=None)
        self.stack = []
        self.path = []

    def coverage(self, cmds, rule):
        got, rc = run_tool(self.tool, self.d, script(W, H, rule, cmds, self.st['T'], self.st['tol'],
                                                     0xFFFFFFFF, 0), W, H)
        assert got is not None, f"host_path failed ({rc}) for {cmds[-3:]}"
        return got[..., 3]

    def paint(self, p):
        if p[0] == 'solid':
            return np.full((H, W), p[1], np.int64)
        _, kind, spread, geom, stops, m = p
        return colours(W, H, kind, spread, geom, stops, mul(self.st['T'], m))

    def draw(self, cov, col, alpha=None):
        a = self.st['alpha'] if alpha is None else alpha
        if a != 255:
            cov = div255(cov * a)
        if self.st['clip'] is not None:
            cov = div255(cov * self.st['clip'])
        self.bufs[self.st['target']] = composite(col, cov, self.bufs[self.st['target']])

    def fill_path(self, cmds):
        self.draw(self.coverage(cmds, self.st['rule']), self.paint(self.st['fill']))

    def stroke_path(self, cmds):
        extra = []
        if self.st['dash']:
            extra.append(('dash', *self.st['dash']))
        extra.append(('stroke', *self.st['style']))
        self.draw(self.coverage(cmds + extra, 0), self.paint(self.st['stroke']))

    def run(self, cmds):
        st = self.st
        for name, *a in cmds:
            if name in PATH_OPS:
                self.path.append((name, *a))
            elif name == 'new_path':
                self.path = []
            elif name == 'fill':
                self.fill_path(self.path)
            elif name == 'stroke':
                self.stroke_path(self.path)
            elif name == 'clip':
                cov = self.coverage(self.path, st['rule'])
                st['clip'] = cov if st['clip'] is None else div255(cov * st['clip'])
            elif name == 'save':
                self.stack.append(dict(st))
                st = self.st = dict(st, layer=None)
            elif name == 'restore':
                st = self.st = self.stack.pop()
            elif name == 'set_transform':
                st['T'] = list(a)
            elif name == 'transform':
                st['T'] = mul(st['T'], list(a))
            elif name == 'translate':
                st['T'] = mul(st['T'], [1.0, 0, 0, 1.0, a[0], a[1]])
            elif name == 'scale':
                st['T'] = mul(st['T'], [a[0], 0, 0, a[1], 0, 0])
            elif name == 'rotate':
                c, s = math.cos(a[0]), math.sin(a[0])
                st['T'] = mul(st['T'], [c, s, -s, c, 0, 0])
            elif name in ('fill_color', 'stroke_color'):
                st[name[:-6]] = ('solid', int(a[0]), [1.0, 0, 0, 1.0, 0, 0])
            elif name in ('fill_gradient', 'stroke_gradient'):
                kind, spread, geom, stops, m = a
                st[name[:-9]] = ('grad', kind, spread, geom, stops, list(m))
            elif name == 'stroke_style':
                st['style'] = tuple(a)
            elif name == 'dash':
                st['dash'] = (a[0], list(a[1])) if a[1] else None
            elif name == 'alpha':
                st['alpha'] = int(a[0])
            elif name == 'rule':
                st['rule'] = int(a[0])
            elif name == 'tolerance':
                st['tol'] = a[0] if a[0] > 0 else DEFAULT_TOL
            elif name == 'fill_rect':
                self.fill_path([('rect', *a)])
            elif name == 'stroke_rect':
                self.stroke_path([('rect', *a)])
            elif name == 'draw_image':
                x, y, w, h, img = a
                m = mul(st['T'], [w / img.shape[1], 0.0, 0.0, h / img.shape[0], x, y])
                cov = self.coverage([('rect', x, y, w, h)], 0)
                self.draw(cov, image_colours(W, H, img, PAD, PAD, BILINEAR, m))
            elif name == 'clear':
                self.bufs[st['target']] = np.full((H, W), int(a[0]), np.int64)
            elif name == 'begin_layer':
                self.stack.append(dict(st))
                self.bufs.append(np.zeros((H, W), np.int64))
                st = self.st = dict(st, layer=int(a[0]), alpha=255, clip=None, target=len(self.bufs) - 1)
            elif name == 'end_layer':
                layer, la = self.bufs[st['target']], st['layer']
                st = self.st = self.stack.pop()
                self.draw(np.full((H, W), 255, np.int64), layer, div255(st['alpha'] * la))
        return self.bufs[0]


def cases(rng):
    circle = [('circle', 20, 16, 11)]
    tri = [('move', 4, 28), ('line', 30, 3), ('line', 44, 26), ('close',)]
    pentagram = [('move', 24 + 14 * math.sin(k * 4 * math.pi / 5), 16 - 14 * math.cos(k * 4 * math.pi / 5))
                 if k == 0 else ('line', 24 + 14 * math.sin(k * 4 * math.pi / 5), 16 - 14 * math.cos(k * 4 * math.pi / 5))
                 for k in range(5)] + [('close',)]
    grad = (LINEAR, REFLECT, [0, 0, 6, 3], [(0, 0xFFFF0000), (0.5, 0x8000FF00), (1, 0xFF0000FF)])
    rad = (RADIAL, PAD, [0, 0, 10], [(0, 0xFFFFFFFF), (1, 0xFF202080)])
    shear = [1.0, 0.0, 0.5, 1.0, -4.0, 1.0]     # det exactly 1
    turn = [0.0, 1.0, -1.0, 0.0, 40.0, 2.0]     # 90 degrees, det 1
    img = random_image(rng, 5, 4)
    yield "fill transformed", [('translate', 6, 3), ('scale', 1.5, 0.75), ('fill_color', 0xFFE08020)] + circle + [('fill',)]
    yield "save/restore state", ([('fill_color', 0xFFFF0000)] + circle + [('fill',), ('save',), ('translate', 14, 2),
                                 ('fill_color', 0xC0008000), ('fill',), ('restore',), ('new_path',)]
                                 + [('rect', 30, 20, 15, 10), ('fill',)])
    yield "gradient user space", [('translate', 10, 4), ('scale', 2, 1.5), ('fill_gradient', *grad, [1.0, 0, 0, 1.0, 2, 1]),
                                  ('rect', 0, 0, 18, 16), ('fill',)]
    yield "radial paint matrix", [('fill_gradient', *rad, [1.6, 0.0, 0.3, 0.9, 24, 16]), ('rect', 0, 0, 48, 32), ('fill',)]
    yield "stroke sheared", [('transform', *shear), ('stroke_color', 0xFF10C0F0), ('stroke_style', 3, 4, 1, 1)] + tri + [('stroke',)]
    yield "stroke turned", [('set_transform', *turn), ('stroke_style', 2.5, 4, 0, 2)] + tri + [('stroke',)]
    yield "dashed stroke", [('translate', 1, 1), ('stroke_style', 2, 4, 1, 1), ('dash', 1.5, [5, 3])] + circle + [('stroke',)]
    yield "dash off again", [('stroke_style', 2, 4, 0, 0), ('dash', 0, [4, 4]), ('dash', 0, [])] + tri + [('stroke',)]
    yield "gradient stroke", [('stroke_gradient', *grad, [1.0, 0, 0, 1.0, 0, 0]), ('stroke_style', 4, 4, 2, 0)] + tri + [('stroke',)]
    yield "clip and restore", ([('save',)] + circle + [('clip',), ('new_path',), ('fill_color', 0xFF00A0FF),
                               ('fill_rect', 0, 0, 48, 32), ('restore',), ('fill_color', 0x60FF0000),
                               ('fill_rect', 4, 4, 40, 10)])
    yield "clip twice", circle + [('clip',), ('new_path',)] + tri + [('clip',), ('new_path',), ('fill_rect', 0, 0, 48, 32)]
    yield "clip nested levels", (circle + [('clip',), ('new_path',), ('save',)] + tri + [('clip',), ('new_path',),
                                 ('save',), ('rect', 20, 0, 30, 32), ('clip',), ('fill_color', 0xFFFFFF00),
                                 ('fill_rect', 0, 0, 48, 32), ('restore',), ('fill_color', 0x8000FF00),
                                 ('fill_rect', 0, 0, 48, 32), ('restore',), ('fill_color', 0x40000080),
                                 ('fill_rect', 0, 0, 48, 32)])
    yield "clip transformed", [('translate', 20, 2), ('rotate', 0.6)] + [('rect', 0, 0, 16, 12), ('clip',), ('new_path',),
                               ('set_transform', 1, 0, 0, 1, 0, 0), ('fill_color', 0xFFFFFFFF), ('fill_rect', 0, 0, 48, 32)]
    yield "global alpha", [('alpha', 128), ('fill_color', 0xFFFF0000)] + circle + [('fill',), ('new_path',), ('alpha', 77),
                           ('fill_color', 0xFF0000FF), ('fill_rect', 18, 8, 28, 20)]
    yield "alpha under clip", tri + [('clip',), ('new_path',), ('alpha', 150), ('fill_gradient', *rad, [1.0, 0, 0, 1.0, 24, 16]),
                                     ('fill_rect', 0, 0, 48, 32)]
    yield "even-odd", [('rule', 1)] + pentagram + [('fill',), ('rule', 0), ('new_path',), ('translate', 10, 0),
                                                  ('fill_color', 0x80FFFFFF)] + pentagram + [('fill',)]
    yield "rects", [('fill_color', 0xFF804020), ('fill_rect', 3.5, 4.25, 20, 11), ('stroke_color', 0xFFFFFFFF),
                    ('stroke_style', 1.5, 4, 0, 0), ('stroke_rect', 3.5, 4.25, 20, 11), ('transform', *shear),
                    ('stroke_rect', 26, 14, 16, 12)]
    yield "draw image", [('translate', 4, 3), ('scale', 1.25, 1.1), ('draw_image', 2, 1, 25, 19, img)]
    yield "image clipped alpha", circle + [('clip',), ('alpha', 180), ('draw_image', 0, 0, 48, 32, img)]
    yield "clear", [('fill_rect', 0, 0, 10, 10), ('clear', 0xFF101010), ('fill_color', 0xFF00FF00)] + circle + [('fill',)]
    yield "layer opacity", ([('begin_layer', 128), ('fill_color', 0xFFFF0000)] + circle + [('fill',), ('new_path',),
                            ('fill_color', 0xFF0000FF), ('circle', 30, 16, 11), ('fill',), ('end_layer',)])
    yield "layer under clip", (tri + [('clip',), ('new_path',), ('alpha', 200), ('begin_layer', 160), ('fill_color', 0xFFFFFF00),
                               ('fill_rect', 0, 0, 48, 32), ('fill_color', 0xFF0000FF)] + circle + [('fill',), ('end_layer',)])
    yield "nested layers", ([('begin_layer', 200), ('fill_color', 0xFFFF0000), ('fill_rect', 2, 2, 30, 20), ('begin_layer', 100),
                             ('fill_color', 0xFF00FF00)] + circle + [('fill',), ('end_layer',), ('fill_color', 0x800000FF),
                             ('fill_rect', 20, 10, 25, 20), ('end_layer',)])
    yield "clip inside layer", ([('begin_layer', 220)] + circle + [('clip',), ('new_path',), ('fill_color', 0xFFFFFFFF),
                                ('fill_rect', 0, 0, 48, 32), ('end_layer',), ('fill_color', 0x80FF0000), ('fill_rect', 0, 0, 20, 32)])
    yield "layer reused", ([('begin_layer', 255), ('fill_color', 0xFFFF0000), ('fill_rect', 0, 0, 24, 32), ('end_layer',),
                           ('begin_layer', 128), ('fill_color', 0xFF00FF00), ('fill_rect', 20, 0, 28, 16), ('end_layer',)])
    yield "clip mask reused", ([('save',)] + circle + [('clip',), ('new_path',), ('restore',),
                               ('save',)] + tri + [('clip',), ('new_path',), ('fill_rect', 0, 0, 48, 32), ('restore',),
                               ('fill_color', 0x5000FFFF), ('fill_rect', 0, 0, 48, 32)])
    for i in range(6):
        cmds = []
        depth = 0
        for _ in range(rng.randint(4, 10)):
            r = rng.random()
            if r < 0.12:
                cmds.append(('save',))
                depth += 1
            elif r < 0.2 and depth:
                cmds.append(('restore',))
                depth -= 1
            elif r < 0.3:
                cmds.append(('translate', rng.uniform(-8, 8), rng.uniform(-6, 6)))
            elif r < 0.38:
                cmds.append(('fill_color', rng.getrandbits(24) | (rng.choice([255, 255, 128]) << 24)))
            elif r < 0.45:
                cmds.append(('alpha', rng.randint(60, 255)))
            elif r < 0.55:
                cmds += [('new_path',), ('ellipse', rng.uniform(8, 40), rng.uniform(6, 26), rng.uniform(4, 16),
                                          rng.uniform(4, 12)), ('clip',)]
            elif r < 0.62:
                cmds.append(('fill_gradient', *grad, [1.0, 0, 0, 1.0, rng.uniform(0, 20), 0]))
            else:
                cmds += [('new_path',), ('ellipse', rng.uniform(8, 40), rng.uniform(6, 26), rng.uniform(4, 18),
                                          rng.uniform(4, 14)), ('fill',)]
        yield f"random {i}", cmds


def main():
    ctx_tool, path_tool = (os.path.abspath(p) for p in sys.argv[1:3])
    rng = random.Random(int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1)
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_ctx.") as d:
        def run_ctx(cmds):
            sp, raw = os.path.join(d, "c.bin"), os.path.join(d, "c.raw")
            open(sp, "wb").write(encode(cmds))
            r = subprocess.run([ctx_tool, sp, raw], capture_output=True, timeout=60)
            if r.returncode:
                return None, r.returncode
            return np.frombuffer(open(raw, "rb").read(), np.uint8).reshape(H, W, 4).astype(np.int64), 0

        for name, cmds in cases(rng):
            total += 1
            got, rc = run_ctx(cmds)
            if got is None:
                print(f"FAIL  {name:22} exit {rc}")
                failed += 1
                continue
            want = Ref(path_tool, d).run(cmds)
            want_px = np.stack([(want >> (8 * k)) & 255 for k in range(4)], axis=-1)
            diff = np.abs(got - want_px).max(axis=-1)
            off = int((diff > 1).sum())
            ok = off <= 3
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:22} max_diff={int(diff.max()):3d} pixels_off={off}")
        for name, cmds in (("restore underflow", [('restore',)]),
                           ("save overflow", [('save',)] * 33),
                           ("end without layer", [('end_layer',)]),
                           ("alpha > 255", [('alpha', 256)]),
                           ("bad rule", [('rule', 2)]),
                           ("bad stroke width", [('stroke_style', 0, 4, 0, 0), ('rect', 1, 1, 5, 5), ('stroke',)]),
                           ("bad dash", [('dash', 0, [0, 0]), ('rect', 1, 1, 5, 5), ('stroke',)])):
            total += 1
            _, rc = run_ctx(cmds)
            ok = rc == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  invalid {name:20} exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

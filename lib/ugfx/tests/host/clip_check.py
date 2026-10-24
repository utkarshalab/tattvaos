#!/usr/bin/env python3
"""Check ugfx clipping and masks: path clips (anti-aliased, nested), rectangle
clips, inverted clips, image alpha and luminance masks, clipped solid,
gradient and image fills.

Usage: clip_check.py <host_path binary> [--seed N]

The reference keeps the clip as an A8 array. A path clip takes the path's
coverage (rendered alone in solid white over transparent black, so alpha
is coverage) times the current clip, x / 255 rounded exactly as ugfx does;
a rectangle clip multiplies by a 0/255 box; invert is 255 - m; image masks
take alpha, or (13926 R + 46884 G + 4725 B + 32768) >> 16 of premultiplied
channels. The final fill's coverage is multiplied by the clip the same way
and composited source-over. Every pixel must match exactly.

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
from paint_check import (LINEAR, PAD, REPEAT, BILINEAR, colours, composite, div255,  # noqa: E402
                         image_colours, random_image)

W, H = 48, 32
BG = 0xFF305070


class Ref:
    def __init__(self, tool, d, rule, matrix):
        self.tool, self.d, self.rule, self.matrix = tool, d, rule, matrix
        self.clip = None

    def coverage(self, cmds):
        got, rc = run_tool(self.tool, self.d, script(W, H, self.rule, cmds, self.matrix, 0.02, 0xFFFFFFFF, 0), W, H)
        assert got is not None, f"coverage run failed ({rc})"
        return got[..., 3]

    def combine(self, m):
        self.clip = m if self.clip is None else div255(self.clip * m)

    def apply(self, op, arg):
        if op == 'clip':
            cov = self.coverage(arg)
            self.clip = cov if self.clip is None else div255(cov * self.clip)
        elif op == 'clip_rect':
            x, y, w, h = (int(v) for v in arg)
            m = np.zeros((H, W), np.int64)
            m[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)] = 255
            self.combine(m)
        elif op == 'clip_invert':
            self.clip = 255 - (np.full((H, W), 255, np.int64) if self.clip is None else self.clip)
        elif op == 'mask_image':
            img, kind = arg
            m = np.zeros((H, W), np.int64)
            ih, iw = img.shape
            if kind == 0:
                v = (img >> 24) & 255
            else:
                v = (13926 * ((img >> 16) & 255) + 46884 * ((img >> 8) & 255) + 4725 * (img & 255) + 32768) >> 16
                v = np.minimum(v, 255)
            m[:min(ih, H), :min(iw, W)] = v[:H, :W]
            self.combine(m)
        elif op == 'clip_none':
            self.clip = None


def to_cmds(ops):
    out = []
    for op, arg in ops:
        if op == 'clip':
            out += arg + [('clip',)]
        elif op == 'clip_rect':
            out.append(('clip_rect', *arg))
        elif op == 'mask_image':
            img, kind = arg
            out.append(('mask_image', img.shape[1], img.shape[0], kind, [int(p) for p in img.reshape(-1)]))
        else:
            out.append((op,))
    return out


def cases(rng):
    rect = [('rect', 0, 0, W, H)]
    circle = [('circle', 24, 16, 12.6)]
    star = [('star', 24, 16, 15, 6, 5, 0.3)]
    tri = [('polygon', [(3, 29), (30, 2), (45, 27)])]
    rot_rect = [('move', 24, 1), ('line', 46, 16), ('line', 24, 31), ('line', 2, 16), ('close',)]
    solid = ('solid', 0xFFE08020)
    grad = ('paint', LINEAR, REPEAT, [4, 0, 20, 10], [(0, 0xFFFF0000), (0.5, 0x8000FF00), (1, 0xFF0000FF)])
    img = random_image(rng, 6, 5)
    imgpaint = ('image', img, REPEAT, REPEAT, BILINEAR, [3, 0, 0, 3, 1, 2])
    yield "circle clip", 0, None, [('clip', circle)], rect, solid
    yield "translucent fill", 0, None, [('clip', circle)], rect, ('solid', 0x80402010)
    pentagram = [('polygon', [(24 + 15 * math.sin(k * 4 * math.pi / 5), 16 - 15 * math.cos(k * 4 * math.pi / 5))
                              for k in range(5)])]
    yield "pentagram even-odd", 1, None, [('clip', pentagram)], rect, solid
    yield "pentagram nonzero", 0, None, [('clip', pentagram)], rect, solid
    yield "nested clips", 0, None, [('clip', circle), ('clip', rot_rect)], rect, solid
    yield "three clips", 0, None, [('clip', tri), ('clip', circle), ('clip', rot_rect)], rect, solid
    yield "rect clip", 0, None, [('clip_rect', (10, 6, 25, 15))], circle, solid
    yield "rect then path", 0, None, [('clip_rect', (-5, 4, 30, 40)), ('clip', star)], rect, solid
    yield "path then rect", 0, None, [('clip', circle), ('clip_rect', (20, -3, 60, 20))], rect, solid
    yield "inverted (hole)", 0, None, [('clip', circle), ('clip_invert', None)], rect, solid
    yield "inverted nothing", 0, None, [('clip_invert', None)], rect, solid
    yield "double invert", 0, None, [('clip', star), ('clip_invert', None), ('clip_invert', None)], rect, solid
    yield "clip outside", 0, None, [('clip', [('circle', -30, -30, 10)])], rect, solid
    yield "clip removed", 0, None, [('clip', circle), ('clip_none', None)], star, solid
    yield "alpha mask", 0, None, [('mask_image', (random_image(rng, 40, 25), 0))], rect, solid
    yield "luminance mask", 0, None, [('mask_image', (random_image(rng, 60, 40), 1))], rect, solid
    yield "mask then path", 0, None, [('mask_image', (random_image(rng, 30, 30), 0)), ('clip', circle)], rect, solid
    yield "gradient clipped", 0, None, [('clip', star)], rect, grad
    yield "image clipped", 0, None, [('clip', circle), ('clip', tri)], rect, imgpaint
    yield "stroke as clip", 0, None, [('clip', circle + [('stroke', 5, 4, 1, 1)])], rect, grad
    yield "clipped shape", 0, None, [('clip', rot_rect)], circle, solid
    yield "with matrix", 0, [1.3, 0.2, -0.3, 1.1, 2, -3], [('clip', circle), ('clip', tri)], rect, solid
    for i in range(8):
        ops = []
        for _ in range(rng.randint(1, 3)):
            kind = rng.random()
            if kind < 0.55:
                shape = [('ellipse', rng.uniform(5, 43), rng.uniform(4, 28), rng.uniform(3, 25), rng.uniform(3, 18))]
                if rng.random() < 0.3:
                    shape = [('star', rng.uniform(10, 38), rng.uniform(8, 24), rng.uniform(8, 20), rng.uniform(2, 8),
                              rng.randint(3, 8), rng.uniform(0, 3))]
                ops.append(('clip', shape))
            elif kind < 0.8:
                ops.append(('clip_rect', (rng.randint(-10, 40), rng.randint(-10, 25), rng.randint(0, 50), rng.randint(0, 35))))
            elif kind < 0.9:
                ops.append(('clip_invert', None))
            else:
                ops.append(('mask_image', (random_image(rng, rng.randint(1, 50), rng.randint(1, 36)), rng.randint(0, 1))))
        fill = [('ellipse', rng.uniform(10, 38), rng.uniform(8, 24), rng.uniform(6, 26), rng.uniform(5, 18))]
        yield f"random {i}", rng.randint(0, 1), None, ops, fill, rng.choice([solid, grad, imgpaint])


def paint_cmds(paint):
    if paint[0] == 'solid':
        return []
    if paint[0] == 'paint':
        return [paint]
    _, img, ex, ey, filt, m = paint
    return [('image', img.shape[1], img.shape[0], ex, ey, filt, [int(p) for p in img.reshape(-1)]),
            ('paint_transform', *m)]


def paint_colours(paint):
    if paint[0] == 'solid':
        return np.full((H, W), paint[1], np.int64)
    if paint[0] == 'paint':
        _, kind, spread, geom, stops = paint
        return colours(W, H, kind, spread, geom, stops, None)
    _, img, ex, ey, filt, m = paint
    return image_colours(W, H, img, ex, ey, filt, m)


def main():
    tool = os.path.abspath(sys.argv[1])
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1
    rng = random.Random(seed)
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_clip.") as d:
        for name, rule, matrix, ops, fill, paint in cases(rng):
            total += 1
            colour = paint[1] if paint[0] == 'solid' else 0xFFFFFFFF
            cmds = to_cmds(ops) + fill + paint_cmds(paint)
            got, rc = run_tool(tool, d, script(W, H, rule, cmds, matrix, 0.02, colour, BG), W, H)
            if got is None:
                print(f"FAIL  {name:20} exit {rc}")
                failed += 1
                continue
            ref = Ref(tool, d, rule, matrix)
            for op, arg in ops:
                ref.apply(op, arg)
            cov = ref.coverage(fill)
            if ref.clip is not None:
                cov = div255(cov * ref.clip)
            want = composite(paint_colours(paint), cov, BG)
            want_px = np.stack([(want >> (8 * k)) & 255 for k in range(4)], axis=-1)
            diff = np.abs(got - want_px).max(axis=-1)
            off = int((diff > 0).sum())
            ok = off == 0
            failed += not ok
            drawn = int((cov > 0).sum())
            print(f"{'ok  ' if ok else 'FAIL'}  {name:20} max_diff={int(diff.max()):3d} pixels_off={off} drawn={drawn}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

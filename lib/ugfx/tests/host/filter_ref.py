#!/usr/bin/env python3
"""A model of lib/ugfx/2d/filter.asm: filter graphs over a premultiplied
BGRA layer, with the same integer and float steps.

    apply(buf, region, prims) -> the filtered buffer
    buf     numpy int64 (H, W) of packed premultiplied BGRA
    region  (x0, y0, x1, y1) device pixels
    prims   dicts: type, in1, in2, linear, sub (x0, y0, x1, y1), p (8 floats),
            var (list of floats)

Used by ctx_check.py (the filter opcode) and svg_check.py. Development-machine
tooling only; not part of any OS image.
"""
import math

import numpy as np

FLOOD, OFFSET, BLUR, MERGE, BLEND, COMPOSITE, COLORMATRIX, TRANSFER, MORPHOLOGY, TILE = range(10)
BLUR_K = 1.8799712059732503


def _to_linear(c):
    v = c / 255
    v = v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return int(v * 255 + 0.5)


def _to_srgb(c):
    v = c / 255
    v = v * 12.92 if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return int(v * 255 + 0.5)


TO_LINEAR = np.array([_to_linear(c) for c in range(256)], np.int64)
TO_SRGB = np.array([_to_srgb(c) for c in range(256)], np.int64)


def div255(x):
    x = x + 128
    return (x + (x >> 8)) >> 8


def split(buf):
    return np.stack([(buf >> s) & 255 for s in (0, 8, 16, 24)], axis=-1)


def join(ch):
    return ch[..., 0] | ch[..., 1] << 8 | ch[..., 2] << 16 | ch[..., 3] << 24


def unpremul(c, a):
    safe = np.maximum(a, 1)
    return np.where(a > 0, np.minimum(255, (c * 255 + a // 2) // safe), 0)


def byte(v):
    """fe_byte: clamped to [0, 1], (int)(v 255 + 0.5)."""
    return int(min(max(v, 0.0), 1.0) * 255.0 + 0.5)


def clamp_rect(r, lim):
    x0 = max(r[0], lim[0])
    y0 = max(r[1], lim[1])
    x1 = max(min(r[2], lim[2]), x0)
    y1 = max(min(r[3], lim[3]), y0)
    return x0, y0, x1, y1


def convert(ch, table, rect):
    out = ch.copy()
    x0, y0, x1, y1 = rect
    a = ch[y0:y1, x0:x1, 3]
    for c in range(3):
        u = unpremul(ch[y0:y1, x0:x1, c], a)
        out[y0:y1, x0:x1, c] = div255(table[u] * a)
    zero = a == 0
    for c in range(4):
        out[y0:y1, x0:x1, c][zero] = 0
    return out


def apply(buf, region, prims):
    h, w = buf.shape
    r = clamp_rect(region, (0, 0, w, h))
    x0, y0, x1, y1 = r
    src = np.zeros((h, w, 4), np.int64)
    src[y0:y1, x0:x1] = split(buf)[y0:y1, x0:x1]
    results, tags = [], []

    def inside(rect):
        m = np.zeros((h, w), bool)
        m[rect[1]:rect[3], rect[0]:rect[2]] = True
        return m

    def get(idx, linear):
        if idx == -1:
            ch, tag = src, 0
        elif idx == -2:
            ch = np.zeros_like(src)
            ch[..., 3] = src[..., 3]
            return ch
        elif idx == -3:
            return np.zeros_like(src)
        else:
            ch, tag = results[idx], tags[idx]
        if tag != linear:
            ch = convert(ch, TO_LINEAR if linear else TO_SRGB, r)
        return ch

    for i, pr in enumerate(prims):
        sub = clamp_rect(pr["sub"], r)
        lin = pr["linear"]
        p = list(pr["p"]) + [0.0] * (8 - len(pr["p"]))
        var = pr.get("var", [])
        in1 = get(pr["in1"], lin)
        in2 = get(pr["in2"], lin)
        out = np.zeros_like(src)
        sm = inside(sub)
        t = pr["type"]
        if t == FLOOD:
            c = int(p[0])
            a = c >> 24
            px = [c & 255, c >> 8 & 255, c >> 16 & 255]
            if lin:
                px = [int(TO_LINEAR[v]) for v in px]
            v = [int(div255(np.int64(v * a))) for v in px] + [a]
            out[sm] = v
        elif t == OFFSET:
            dx, dy = int(round(p[0])), int(round(p[1]))
            ys, xs = np.nonzero(sm)
            sx, sy = xs - dx, ys - dy
            ok = (sx >= x0) & (sx < x1) & (sy >= y0) & (sy < y1)
            out[ys[ok], xs[ok]] = in1[sy[ok], sx[ok]]
        elif t == BLUR:
            work = in1[y0:y1, x0:x1].copy()
            for axis in (0, 1):
                s = p[axis]
                if not s > 0:
                    continue
                d = int(min(s * BLUR_K + 0.5, 2048.0))
                if d < 2:
                    continue
                if d % 2:
                    passes = [((d - 1) // 2, (d - 1) // 2, d)] * 3
                else:
                    passes = [(d // 2, d // 2 - 1, d), (d // 2 - 1, d // 2, d), (d // 2, d // 2, d + 1)]
                ax = 1 if axis == 0 else 0
                for lo, hi, n in passes:
                    work = box(work, ax, lo, hi, n)
            full = np.zeros_like(src)
            full[y0:y1, x0:x1] = work
            out[sm] = full[sm]
        elif t == MERGE:
            for idx in var:
                s_ = get(int(idx), lin)
                out[sm] = over(s_[sm], out[sm])
        elif t == BLEND:
            out[sm] = blend(in1[sm], in2[sm], int(p[0]))
        elif t == COMPOSITE:
            op = int(p[0])
            if op == 5:
                out[sm] = arithmetic(in1[sm], in2[sm], p[1:5])
            else:
                out[sm] = porter_duff(in1[sm], in2[sm], op)
        elif t == COLORMATRIX:
            out[sm] = colormatrix(in1[sm], var) if len(var) >= 20 else in1[sm]
        elif t == TRANSFER:
            out[sm] = transfer(in1[sm], var)
        elif t == MORPHOLOGY:
            rx, ry = int(round(p[1])), int(round(p[2]))
            if rx <= 0 or ry <= 0:
                out[sm] = in1[sm]
            else:
                out[sm] = morph(in1, r, rx, ry, int(p[0]) == 1)[sm]
        elif t == TILE:
            tr = clamp_rect(prims[pr["in1"]]["sub"], r) if pr["in1"] >= 0 else r
            tw, th = tr[2] - tr[0], tr[3] - tr[1]
            if tw > 0 and th > 0:
                ys, xs = np.nonzero(sm)
                out[ys, xs] = in1[tr[1] + (ys - tr[1]) % th, tr[0] + (xs - tr[0]) % tw]
        results.append(out)
        tags.append(lin)
    final = np.zeros((h, w), np.int64)
    if prims:
        last = results[-1]
        if tags[-1]:
            last = convert(last, TO_SRGB, r)
        final[y0:y1, x0:x1] = join(last)[y0:y1, x0:x1]
    return final


def box(work, axis, lo, hi, n):
    """One box pass along axis: the window i - lo .. i + hi, (sum + n / 2) / n."""
    length = work.shape[axis]
    pad = np.zeros_like(work)
    c = np.cumsum(work, axis=axis)
    c = np.concatenate([np.zeros_like(np.take(c, [0], axis=axis)), c], axis=axis)
    idx = np.arange(length)
    a = np.clip(idx - lo, 0, length)
    b = np.clip(idx + hi + 1, 0, length)
    sums = np.take(c, b, axis=axis) - np.take(c, a, axis=axis)
    del pad
    return (sums + n // 2) // n


def over(s, d):
    return np.minimum(255, s + div255(d * (255 - s[..., 3:4])))


def blend(s, b, mode):
    a_s, a_b = s[..., 3:4], b[..., 3:4]
    cs, cb = s[..., :3], b[..., :3]
    s1 = div255(cs * (255 - a_b))
    s2 = div255(cb * (255 - a_s))
    m = div255(cs * cb)
    if mode == 1:
        c = s1 + s2 + m
    elif mode == 2:
        c = cs + cb - m
    elif mode == 3:
        c = np.minimum(cs + s2, cb + s1)
    elif mode == 4:
        c = np.maximum(cs + s2, cb + s1)
    else:
        c = cs + s2
    c = np.minimum(c, 255)
    a = a_s + a_b - div255(a_s * a_b)
    return np.concatenate([c, a], axis=-1)


def porter_duff(a, b, op):
    aa, ab = a[..., 3:4], b[..., 3:4]
    one = np.full_like(aa, 255)
    fa = {0: one, 1: ab, 2: 255 - ab, 3: ab, 4: 255 - ab}[op]
    fb = {0: 255 - aa, 1: 0 * aa, 2: 0 * aa, 3: 255 - aa, 4: 255 - aa}[op]
    return np.minimum(255, div255(a * fa) + div255(b * fb))


def arithmetic(a, b, k):
    out = np.zeros_like(a)
    for idx in np.ndindex(a.shape[:-1]):
        alpha = 0
        for ch in (3, 2, 1, 0):
            i1, i2 = a[idx + (ch,)] / 255.0, b[idx + (ch,)] / 255.0
            v = k[0] * i1 * i2 + k[1] * i1 + k[2] * i2 + k[3]
            v = byte(v)
            if ch == 3:
                alpha = v
            elif v > alpha:
                v = alpha
            out[idx + (ch,)] = v
    return out


def straight(px):
    """fe_unpremul_px: r, g, b, a in [0, 1] (r, g, b unpremultiplied)."""
    a = int(px[3])
    rgb = []
    for ch in (2, 1, 0):
        c = int(px[ch])
        u = min(255, (c * 255 + a // 2) // a) if a else 0
        rgb.append(u / 255.0)
    return rgb + [a / 255.0]


def premul_out(r, g, b, a):
    return [div255(b * a), div255(g * a), div255(r * a), a]


def colormatrix(px, m):
    out = np.zeros_like(px)
    for i in range(px.shape[0]):
        v = straight(px[i])
        res = []
        for row in range(4):
            q = m[row * 5: row * 5 + 5]
            res.append(byte(q[0] * v[0] + q[1] * v[1] + q[2] * v[2] + q[3] * v[3] + q[4]))
        out[i] = premul_out(*res)
    return out


def func_value(f, c):
    kind = int(f[0])
    n = int(f[6])
    table = f[7:7 + n]
    if kind == 1 and n:
        x = (n - 1) * c
        k = int(x)
        if k >= n - 1:
            return table[n - 1]
        return table[k] + (x - k) * (table[k + 1] - table[k])
    if kind == 2 and n:
        k = int(n * c)
        return table[min(k, n - 1)]
    if kind == 3:
        return c * f[1] + f[2]
    if kind == 4:
        return math.pow(c, f[4]) * f[3] + f[5]
    return c


def transfer_luts(var):
    luts, i = [], 0
    for _ in range(4):
        if i + 7 > len(var) or int(var[i + 6]) < 0 or i + 7 + int(var[i + 6]) > len(var):
            break
        f = var[i:i + 7 + int(var[i + 6])]
        luts.append([byte(func_value(f, c / 255.0)) for c in range(256)])
        i += 7 + int(var[i + 6])
    while len(luts) < 4:
        luts.append(list(range(256)))
    return luts


def transfer(px, var):
    luts = transfer_luts(var)
    out = np.zeros_like(px)
    for i in range(px.shape[0]):
        a = int(px[i][3])
        rgb = []
        for ch, lut in zip((2, 1, 0), luts):
            c = int(px[i][ch])
            u = min(255, (c * 255 + a // 2) // a) if a else 0
            rgb.append(lut[u])
        out[i] = premul_out(rgb[0], rgb[1], rgb[2], luts[3][a])
    return out


def morph(ch, r, rx, ry, dilate):
    h, w = ch.shape[:2]
    x0, y0, x1, y1 = r
    pad = np.zeros((h + 2 * ry, w + 2 * rx, 4), np.int64)
    inner = np.zeros_like(ch)
    inner[y0:y1, x0:x1] = ch[y0:y1, x0:x1]
    pad[ry:ry + h, rx:rx + w] = inner
    out = np.full_like(ch, 0 if dilate else 255)
    for dy in range(-ry, ry + 1):
        for dx in range(-rx, rx + 1):
            s = pad[ry + dy:ry + dy + h, rx + dx:rx + dx + w]
            out = np.maximum(out, s) if dilate else np.minimum(out, s)
    return out

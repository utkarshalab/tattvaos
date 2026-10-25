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

(FLOOD, OFFSET, BLUR, MERGE, BLEND, COMPOSITE, COLORMATRIX, TRANSFER, MORPHOLOGY, TILE,
 CONVOLVE, DISPLACE, TURBULENCE, DIFFUSE, SPECULAR, IMAGE) = range(16)
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
        elif t in (CONVOLVE, DISPLACE, TURBULENCE, DIFFUSE, SPECULAR, IMAGE):
            fn = {CONVOLVE: convolve, DISPLACE: displace, TURBULENCE: turbulence,
                  DIFFUSE: lighting, SPECULAR: lighting, IMAGE: image}[t]
            fn(out, in1, in2, r, sub, t, lin, p, var)
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


# --- the per-pixel primitives -------------------------------------------------

def at(ch, x, y, edge, r):
    """fe_at: the pixel at (x, y), outside the region by edge (0 duplicate,
    1 wrap, 2 none)."""
    x0, y0, x1, y1 = r
    if not (x0 <= x < x1):
        if edge == 2:
            return (0, 0, 0, 0)
        x = x0 + (x - x0) % (x1 - x0) if edge == 1 else min(max(x, x0), x1 - 1)
    if not (y0 <= y < y1):
        if edge == 2:
            return (0, 0, 0, 0)
        y = y0 + (y - y0) % (y1 - y0) if edge == 1 else min(max(y, y0), y1 - 1)
    return tuple(int(v) for v in ch[y, x])


def floor_c(v):
    """fe_floor: clamped to +-2^30, NaN 0."""
    if v != v:
        return 0
    return math.floor(min(max(v, -1073741824.0), 1073741824.0))


def channel_u(px, c):
    """fe_channel_u: channel c (BGRA index) unpremultiplied, in [0, 1]."""
    a = px[3]
    if c == 3:
        return a / 255.0
    if a == 0:
        return 0.0
    return min(255, (px[c] * 255 + a // 2) // a) / 255.0


def pixels(sub):
    for y in range(sub[1], sub[3]):
        for x in range(sub[0], sub[2]):
            yield x, y


def convolve(out, in1, in2, r, sub, t, lin, p, var):
    ox, oy = int(p[0]), int(p[1])
    if ox * oy > len(var) or ox <= 0 or oy <= 0:
        return
    tx, ty, edge, keep = int(p[4]), int(p[5]), int(p[6]), p[7] != 0
    for x, y in pixels(sub):
        sums = [0.0] * 4
        for i in range(oy):
            for j in range(ox):
                px = at(in1, x - tx + j, y - ty + i, edge, r)
                k = var[(oy - 1 - i) * ox + (ox - 1 - j)]
                for c in range(4):
                    if c == 3 and keep:
                        continue
                    v = channel_u(px, c) if keep else px[c] / 255.0
                    sums[c] = v * k + sums[c]
        b = [byte(v / p[2] + p[3]) for v in sums]
        if keep:
            a = at(in1, x, y, 2, r)[3]
            out[y, x] = [int(div255(np.int64(b[c] * a))) for c in range(3)] + [a]
        else:
            out[y, x] = [min(b[c], b[3]) for c in range(3)] + [b[3]]


SHIFT_INDEX = (2, 1, 0, 3)                     # R G B A -> BGRA index


def displace(out, in1, in2, r, sub, t, lin, p, var):
    cx, cy = SHIFT_INDEX[int(p[2]) & 3], SHIFT_INDEX[int(p[3]) & 3]
    for x, y in pixels(sub):
        m = tuple(int(v) for v in in2[y, x])
        sx = floor_c((channel_u(m, cx) - 0.5) * p[0] + x + 0.5)
        sy = floor_c((channel_u(m, cy) - 0.5) * p[1] + y + 0.5)
        out[y, x] = at(in1, sx, sy, 2, r)


def px_convert(px, table):
    a = px[3]
    if a == 0:
        return (0, 0, 0, 0)
    return tuple(int(div255(np.int64(int(table[min(255, (px[c] * 255 + a // 2) // a)]) * a)))
                 for c in range(3)) + (a,)


def image(out, in1, in2, r, sub, t, lin, p, var):
    if len(var) < 2:
        return
    iw, ih = int(var[0]), int(var[1])
    pix = var[2:]
    if not (p[2] > 0 and p[3] > 0):
        return
    for x, y in pixels(sub):
        u = floor_c((x + 0.5 - p[0]) / p[2] * iw)
        v = floor_c((y + 0.5 - p[1]) / p[3] * ih)
        if 0 <= u < iw and 0 <= v < ih:
            c = int(pix[v * iw + u])
            px = (c & 255, c >> 8 & 255, c >> 16 & 255, c >> 24 & 255)
            if lin:
                px = px_convert(px, TO_LINEAR)
            out[y, x] = px


def _random(s):
    s = 16807 * (s % 127773) - 2836 * (s // 127773)
    return s + 2147483647 if s <= 0 else s


def turb_tables(seed):
    s = int(min(max(seed, -1073741824.0), 1073741824.0))
    if s <= 0:
        s = -s + 1
    lat = [0] * 514
    grad = [[[0.0, 0.0] for _ in range(514)] for _ in range(4)]
    for k in range(4):
        for i in range(256):
            lat[i] = i
            g = grad[k][i]
            for j in range(2):
                s = _random(s)
                g[j] = ((s % 512) - 256) / 256.0
            n = math.sqrt(g[0] * g[0] + g[1] * g[1])
            g[0], g[1] = (g[0] / n, g[1] / n) if n else (math.nan, math.nan)
    for i in range(255, 0, -1):
        s = _random(s)
        j = s % 256
        lat[i], lat[j] = lat[j], lat[i]
    for i in range(258):
        lat[256 + i] = lat[i]
        for k in range(4):
            grad[k][256 + i] = list(grad[k][i])
    return lat, grad


def _adjust(f, size):
    if f == 0:
        return f
    lo = floor_c(size * f) / size
    hi = -floor_c(-(size * f)) / size
    q = f / lo if lo else math.copysign(math.inf, f)
    return lo if q < hi / f else hi


def turbulence(out, in1, in2, r, sub, t, lin, p, var):
    lat, grad = turb_tables(p[3])
    fx, fy = p[0], p[1]
    stitch = p[4] != 0
    octaves, turb = int(p[2]), p[5] != 0
    m = var[:6]
    st = [0, 0, 0, 0]
    if stitch:
        tx, ty, tw, th = var[6:10]
        fx, fy = _adjust(fx, tw), _adjust(fy, th)
        nw = int(tw * fx + 0.5)
        nh = int(th * fy + 0.5)
        st = [nw, nh, int(tx * fx + 4096.0 + nw), int(ty * fy + 4096.0 + nh)]

    def noise(c, vx, vy, w, h, wx, wy):
        tt = vx + 4096.0
        it = int(tt)
        rx0 = tt - it
        rx1 = rx0 - 1.0
        bx0, bx1 = it, it + 1
        tt = vy + 4096.0
        it = int(tt)
        ry0 = tt - it
        ry1 = ry0 - 1.0
        by0, by1 = it, it + 1
        if stitch:
            bx0 -= w if bx0 >= wx else 0
            bx1 -= w if bx1 >= wx else 0
            by0 -= h if by0 >= wy else 0
            by1 -= h if by1 >= wy else 0
        bx0, bx1, by0, by1 = bx0 & 255, bx1 & 255, by0 & 255, by1 & 255
        i, j = lat[bx0], lat[bx1]
        b00, b10, b01, b11 = lat[i + by0], lat[j + by0], lat[i + by1], lat[j + by1]
        sx = rx0 * rx0 * (3.0 - 2.0 * rx0)
        sy = ry0 * ry0 * (3.0 - 2.0 * ry0)
        g = grad[c]
        u = rx0 * g[b00][0] + ry0 * g[b00][1]
        v = rx1 * g[b10][0] + ry0 * g[b10][1]
        a = u + sx * (v - u)
        u = rx0 * g[b01][0] + ry1 * g[b01][1]
        v = rx1 * g[b11][0] + ry1 * g[b11][1]
        b = u + sx * (v - u)
        return a + sy * (b - a)

    for x, y in pixels(sub):
        X, Y = x + 0.5, y + 0.5
        ux = m[0] * X + m[2] * Y + m[4]
        uy = m[1] * X + m[3] * Y + m[5]
        vals = []
        for c in range(4):
            vx, vy, ratio = ux * fx, uy * fy, 1.0
            w, h, wx, wy = st
            total = 0.0
            for _ in range(octaves):
                n = noise(c, vx, vy, w, h, wx, wy)
                if turb:
                    n = abs(n)
                total = n / ratio + total
                vx, vy, ratio = vx * 2, vy * 2, ratio * 2
                if stitch:
                    w, wx = w * 2, 2 * wx - 4096
                    h, wy = h * 2, 2 * wy - 4096
            v = total * 255.0
            if not turb:
                v = (v + 255.0) * 0.5
            v = min(max(v, 0.0), 255.0) if v == v else 0.0
            vals.append(int(v + 0.5))
        a = vals[3]
        out[y, x] = [int(div255(np.int64(vals[c] * a))) for c in (2, 1, 0)] + [a]


def _unit(x, y, z):
    n = math.sqrt(x * x + y * y + z * z)
    return x / n, y / n, z / n


def lighting(out, in1, in2, r, sub, t, lin, p, var):
    ss = p[0]
    c = int(p[4])
    colour = []
    for sh in (16, 8, 0):
        v = c >> sh & 255
        if lin:
            v = int(TO_LINEAR[v])
        colour.append(v / 255.0)
    light = int(p[3])
    x0, y0, x1, y1 = r
    for x, y in pixels(sub):
        I = [at(in1, x + k % 3 - 1, y + k // 3 - 1, 0, r)[3] / 255.0 for k in range(9)]
        le, ri = float(x > x0), float(x < x1 - 1)
        ab, be = float(y > y0), float(y < y1 - 1)
        nx = ny = 0.0
        if le + ri:
            d = (ab * I[2] + 2 * I[5] + be * I[8]) - (ab * I[0] + 2 * I[3] + be * I[6])
            nx = d * ((0.0 - ss) * (2.0 / ((ab + 2.0 + be) * (le + ri))))
        if ab + be:
            d = (le * I[6] + 2 * I[7] + ri * I[8]) - (le * I[0] + 2 * I[1] + ri * I[2])
            ny = d * ((0.0 - ss) * (2.0 / ((le + 2.0 + ri) * (ab + be))))
        n = math.sqrt(nx * nx + ny * ny + 1.0)
        N = (nx / n, ny / n, 1.0 / n)
        col = list(colour)
        if light == 0:
            L = tuple(var[0:3])
        else:
            L = _unit(var[0] - x, var[1] - y, var[2] - ss * I[4])
            if light == 2:
                S = _unit(var[3] - var[0], var[4] - var[1], var[5] - var[2])
                m = 0.0 - (S[0] * L[0] + S[1] * L[1] + S[2] * L[2])
                if m > 0 and not m < p[6]:
                    f = math.pow(m, p[5])
                    col = [v * f for v in col]
                else:
                    col = [0.0, 0.0, 0.0]
        if t == DIFFUSE:
            k = (N[0] * L[0] + N[1] * L[1] + N[2] * L[2]) * p[1]
            alpha = 255
        else:
            H = _unit(L[0], L[1], L[2] + 1.0)
            nh = max(0.0, H[0] * N[0] + H[1] * N[1] + H[2] * N[2])
            k = math.pow(nh, p[2]) * p[1]
            alpha = None
        bts = [byte(v * k) for v in col]
        if alpha is None:
            alpha = max(bts)
        out[y, x] = [int(div255(np.int64(bts[c] * alpha))) for c in (2, 1, 0)] + [alpha]

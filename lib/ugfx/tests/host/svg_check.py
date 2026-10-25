#!/usr/bin/env python3
"""Check ugfx SVG: parsing (elements, attributes, styles, transforms, colours,
path data, shapes) and drawing.

Usage: svg_check.py <host_ctx binary>

Each document is parsed and drawn by ugfx (ugfx_svg_parse, ugfx_svg_draw)
through host_ctx, and separately turned by tools/svgmodel.py - a model of
the same subset and rules - into the context calls the drawing should
make, which host_ctx then runs. The images must match: exactly where only
arithmetic is involved, within 1 per channel on at most 3 pixels where
arcs or rotations go through trigonometry (umath's last bit may differ
from Python's).

Development-machine tooling only; not part of any OS image.
"""
import math
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import svgmodel  # noqa: E402
from ctx_check import encode  # noqa: E402


def div255(x):
    x += 128
    return (x + (x >> 8)) >> 8


def premul(c):
    a = c >> 24
    return (a << 24) | sum(div255(((c >> s) & 255) * a) << s for s in (0, 8, 16))


def expected_calls(doc, current, x, y, size):
    t = svgmodel.root_matrix(doc, x, y, size)
    return [('save',), ('transform', *t), ('dash', 0, [])] + item_calls(doc.items, current, t) + [('restore',)]


def floor_or_none(v):
    """svg_pattern_paint's floor: None past 2^30 (or NaN)."""
    if v != v or abs(v) >= 1073741824.0:
        return None
    return math.floor(v)


def pattern_calls(rec, it, stroke, alpha, current, t):
    """svg_pattern_paint: the tiles covering the item, in its space t x it.matrix."""
    if not rec.items:
        return []
    b = it.bbox
    bw, bh = b[2] - b[0], b[3] - b[1]
    rx, ry, rw, rh = rec.rect
    if rec.units:
        rx, ry, rw, rh = rx * bw + b[0], ry * bh + b[1], rw * bw, rh * bh
    if not (rw > 0 and rh > 0):
        return []
    c = list(b)
    if stroke:
        e = it.width * max(it.miter, 1.5) * 0.5
        c = [c[0] - e, c[1] - e, c[2] + e, c[3] + e]
    inv = svgmodel.invert(rec.matrix)
    if inv is None:
        return []
    pts = [(inv[0] * x + inv[2] * y + inv[4], inv[1] * x + inv[3] * y + inv[5])
           for x, y in ((c[0], c[1]), (c[2], c[1]), (c[0], c[3]), (c[2], c[3]))]
    p = [min(q[0] for q in pts), min(q[1] for q in pts), max(q[0] for q in pts), max(q[1] for q in pts)]
    i0 = floor_or_none((p[0] - rx) / rw)
    i1 = floor_or_none(0.0 - (p[2] - rx) / rw)
    j0 = floor_or_none((p[1] - ry) / rh)
    j1 = floor_or_none(0.0 - (p[3] - ry) / rh)
    if None in (i0, i1, j0, j1):
        return []
    i1, j1 = -i1, -j1
    if i1 - i0 <= 0 or j1 - j0 <= 0 or i1 - i0 > 4096 or j1 - j0 > 4096 or (i1 - i0) * (j1 - j0) > 4096:
        return []
    tb = svgmodel.mul(t, it.matrix)
    out = [('begin_layer', alpha)] if alpha < 255 else []
    for j in range(j0, j1):
        for i in range(i0, i1):
            move = [1.0, 0.0, 0.0, 1.0, i * rw + rx, j * rh + ry]
            out += [('save',), ('set_transform', *tb), ('transform', *rec.matrix), ('transform', *move),
                    ('transform', rw, 0.0, 0.0, rh, 0.0, 0.0), ('new_path',), ('rect', 0.0, 0.0, 1.0, 1.0), ('clip',),
                    ('set_transform', *tb), ('transform', *rec.matrix), ('transform', *move)]
            base = svgmodel.mul(svgmodel.mul(tb, rec.matrix), move)
            if rec.viewbox:
                m = svgmodel.fit(rec.viewbox, rw, rh, rec.par)
                out.append(('transform', *m))
                base = svgmodel.mul(base, m)
            elif rec.content:
                m = [bw, 0.0, 0.0, bh, 0.0, 0.0]
                out.append(('transform', *m))
                base = svgmodel.mul(base, m)
            out += item_calls(rec.items, current, base) + [('restore',)]
    if alpha < 255:
        out.append(('end_layer',))
    return out


def item_calls(items, current, t):
    """The calls svg_draw_list makes for an item list (t: the context's transform when it begins)."""
    out = []

    def paint(p):
        kind, c = p
        if kind == "current":
            c = (div255((current >> 24) * (c >> 24)) << 24) | (current & 0xFFFFFF)
        return premul(c)

    for it in items:
        if isinstance(it, svgmodel.ImageItem):
            out += [('save',), ('transform', *it.matrix)]
            if it.clip:
                out += [('new_path',)] + it.path + [('clip',)]
            out += [('alpha', it.alpha), ('draw_image', *it.dest, it.image), ('restore',)]
            continue
        if isinstance(it, svgmodel.MarkerItem):
            mk = it.marker
            out += [('save',), ('set_transform', *t), ('transform', *it.matrix)]
            if mk.clip:
                out += [('transform', mk.size[0], 0.0, 0.0, mk.size[1], 0.0, 0.0), ('new_path',),
                        ('rect', 0.0, 0.0, 1.0, 1.0), ('clip',), ('set_transform', *t), ('transform', *it.matrix)]
            base = svgmodel.mul(t, it.matrix)
            if mk.vbm:
                out.append(('transform', *mk.vbm))
                base = svgmodel.mul(base, mk.vbm)
            out += item_calls(mk.items, current, base) + [('restore',)]
            continue
        if isinstance(it, svgmodel.Group):
            if it.kind == "begin":
                if it.clip:
                    out.append(('save',))
                    rec = it.clip
                    while rec:
                        out += [('set_transform', *t), ('transform', *it.matrix)]
                        clip_items = rec.items
                        if rec.units:
                            w, h = it.bbox[2] - it.bbox[0], it.bbox[3] - it.bbox[1]
                            if w > 0 and h > 0:
                                out.append(('transform', w, 0.0, 0.0, h, it.bbox[0], it.bbox[1]))
                            else:
                                clip_items = []
                        out.append(('clip_begin',))
                        for c in clip_items:
                            out += [('save',), ('transform', *c.matrix), ('rule', c.rule), ('new_path',)] + \
                                c.path + [('clip_add',), ('restore',)]
                        out.append(('clip_end',))
                        rec = rec.next
                    out.append(('set_transform', *t))
                if it.mask or it.filter or it.alpha < 255:
                    out.append(('begin_layer', it.alpha))
            else:
                if it.filter:
                    region, prims = svgmodel.filter_device(it.filter, it.begin, t)
                    out.append(('filter', region, prims))
                if it.mask:
                    b, mk = it.begin, it.mask
                    bw, bh = b.bbox[2] - b.bbox[0], b.bbox[3] - b.bbox[1]
                    rx, ry, rw, rh = mk.region
                    if mk.units:
                        rx, ry, rw, rh = rx * bw + b.bbox[0], ry * bh + b.bbox[1], rw * bw, rh * bh
                    out += [('begin_mask',), ('set_transform', *t), ('transform', *b.matrix),
                            ('transform', rw, 0.0, 0.0, rh, rx, ry), ('new_path',), ('rect', 0.0, 0.0, 1.0, 1.0),
                            ('clip',), ('set_transform', *t), ('transform', *b.matrix)]
                    base = svgmodel.mul(t, b.matrix)
                    if not mk.content:
                        out += item_calls(mk.items, current, base)
                    elif bw > 0 and bh > 0:
                        m = [bw, 0.0, 0.0, bh, b.bbox[0], b.bbox[1]]
                        out.append(('transform', *m))
                        out += item_calls(mk.items, current, svgmodel.mul(base, m))
                    out += [('end_mask', mk.mode), ('end_layer',)]
                elif it.filter or it.alpha < 255:
                    out.append(('end_layer',))
                if it.clip:
                    out.append(('restore',))
            continue
        out += [('save',), ('transform', *it.matrix)]
        fill, stroke = [], []
        if it.fill and it.fill[0] == 'pattern':
            fill += [('save',), ('rule', it.rule), ('new_path',)] + it.path + [('clip',)]
            fill += pattern_calls(it.fill[1], it, 0, it.fill[2], current, t) + [('restore',)]
        elif it.fill:
            if it.fill[0] == 'paint':
                _, kind, spread, geom, stops, m, a = it.fill
                fill += [('fill_gradient', kind, spread, geom, stops, m), ('alpha', a)]
            else:
                fill += [('alpha', 255), ('fill_color', paint(it.fill))]
            fill += [('rule', it.rule), ('new_path',)] + it.path + [('fill',)]
        if it.stroke and it.stroke[0] == 'pattern':
            stroke += [('stroke_style', it.width, it.miter, it.join, it.cap)]
            if it.dash:
                stroke.append(('dash', it.dash_off, it.dash))
            stroke += [('save',), ('new_path',)] + it.path + [('clip_stroke',)]
            stroke += pattern_calls(it.stroke[1], it, 1, it.stroke[2], current, t) + [('restore',)]
        elif it.stroke:
            if it.stroke[0] == 'paint':
                _, kind, spread, geom, stops, m, a = it.stroke
                stroke += [('stroke_gradient', kind, spread, geom, stops, m), ('alpha', a)]
            else:
                stroke += [('alpha', 255), ('stroke_color', paint(it.stroke))]
            stroke += [('stroke_style', it.width, it.miter, it.join, it.cap)]
            if it.dash:
                stroke.append(('dash', it.dash_off, it.dash))
            stroke += [('new_path',)] + it.path + [('stroke',)]
        out += (stroke + fill if it.order else fill + stroke) + [('restore',)]
    return out


def farbfeld(data, kind):
    """host_image's decoder: farbfeld (the high bytes), premultiplied."""
    if kind != 0 or data is None or len(data) < 16 or data[:8] != b"farbfeld":
        return None
    w, h = int.from_bytes(data[8:12], "big"), int.from_bytes(data[12:16], "big")
    if len(data) < 16 + w * h * 8:
        return None
    img = np.zeros((h, w), np.int64)
    for i in range(w * h):
        r, g, b, a = data[16 + 8 * i], data[18 + 8 * i], data[20 + 8 * i], data[22 + 8 * i]
        img[i // w, i % w] = a << 24 | div255(r * a) << 16 | div255(g * a) << 8 | div255(b * a)
    return w, h, img


def test_font(font, cp, s, outline):
    """host_font."""
    if cp == 32:
        return 0.3 * s, []
    adv = ((cp % 7) * 0.08 + 0.4) * s
    if font[1] >= 600:
        adv = adv * 1.25
    path = []
    if outline:
        path.append(('rect', s * 0.05, s * -0.7, adv - s * 0.1, s * 0.7))
        if cp % 2:
            path.append(('rect', s * 0.05, s * -0.9, s * 0.15, s * 0.15))
    return adv, path


def ff_bytes(w, h, px):
    return b"farbfeld" + w.to_bytes(4, "big") + h.to_bytes(4, "big") + b"".join(
        bytes([r, r, g, g, b, b, a, a]) for r, g, b, a in px)


def ff_uri(w, h, px, base64=True):
    import base64 as b64
    data = ff_bytes(w, h, px)
    if base64:
        return "data:image/x-farbfeld;base64," + b64.b64encode(data).decode()
    return "data:image/x-farbfeld," + "".join(f"%{c:02X}" if c < 33 or c > 126 or chr(c) in '%"<>&' else chr(c)
                                               for c in data)


IMG = ff_uri(4, 3, [(255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (255, 255, 0, 255),
                    (0, 255, 255, 255), (255, 0, 255, 128), (255, 255, 255, 255), (0, 0, 0, 255),
                    (128, 64, 32, 255), (32, 64, 128, 64), (200, 200, 200, 255), (10, 20, 30, 0)])
IMG_PCT = ff_uri(2, 2, [(255, 128, 0, 255), (0, 128, 255, 255), (128, 0, 255, 200), (0, 0, 0, 255)], False)


def svg(body, attrs='viewBox="0 0 24 24"'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" {attrs}>{body}</svg>'


CASES = [
    ("lines abs/rel", svg('<path d="M2 2 L22 2 L22 10 H12 V22 h-8 v-6 l-2 -2 Z" fill="#1060e0"/>'), False),
    ("implicit lineto", svg('<path d="M2 2 22 2 22 22 m-4 -4 -6 0 0 -6z" fill="#e04010"/>'), False),
    ("cubic + smooth", svg('<path d="M2 12 C2 2 12 2 12 12 S22 22 22 12 s-5 -8 -10 -4 S4 20 2 12z" fill="#208040"/>'), False),
    ("quad + smooth", svg('<path d="M2 12 Q7 2 12 12 T22 12 t-10 8 T2 12 q5 -8 10 -9z" fill="#8020a0"/>'), False),
    ("smooth after line", svg('<path d="M2 2 L10 2 S20 2 20 12 T12 20 Z" fill="#c08000"/>'), False),
    ("numbers", svg('<path d="M.5.5L+23.5-.0e1 2.35e1 1.2E1 -0 2.4e+1zM12 12l.5.5.5-.5" fill="#000"/>'), False),
    ("arcs", svg('<path d="M4 12 A8 8 0 0 1 20 12 A8 8 0 1 1 4 12 Z" fill="#e02060"/>'), True),
    ("arc flags packed", svg('<path d="M4 12a8 4 30 1012 0a8 4 30 01-12 0z" fill="#20a0a0" fill-rule="evenodd"/>'), True),
    ("arc tiny radii", svg('<path d="M3 3 A1 1 0 0 0 21 21 A0.5 2 45 1 0 3 3" fill="#a0a020"/>'), True),
    ("arc zero radius", svg('<path d="M3 12 A0 5 0 0 1 21 12 L12 3z" fill="#304050"/>'), False),
    ("rect plain", svg('<rect x="3" y="4" width="18" height="12" fill="red"/>'), False),
    ("rect rx", svg('<rect x="2" y="2" width="20" height="16" rx="5" fill="blue"/>'), True),
    ("rect rx ry", svg('<rect x="2" y="2" width="20" height="16" rx="8" ry="3" fill="green"/>'), True),
    ("rect rx clamped", svg('<rect x="2" y="6" width="20" height="10" ry="40" fill="navy"/>'), True),
    ("rect zero size", svg('<rect width="0" height="10" fill="red"/><circle cx="12" cy="12" r="0" fill="red"/>'
                           '<circle cx="12" cy="12" r="4"/>'), False),
    ("circle ellipse", svg('<circle cx="8" cy="8" r="6" fill="teal"/><ellipse cx="15" cy="16" rx="7" ry="4" fill="purple"/>'
                           '<ellipse cx="18" cy="6" rx="3" fill="orange"/>'), False),
    ("line poly", svg('<line x1="2" y1="2" x2="22" y2="20" stroke="black" stroke-width="2"/>'
                      '<polyline points="2,22 8,12 14,20 22,4" fill="none" stroke="#c00" stroke-width="1.5"/>'
                      '<polygon points="12 2, 20 10 12 18 4 10 7" fill="#0a0" fill-opacity=".5"/>'), False),
    ("stroke styles", svg('<path d="M3 20 L12 4 L21 20" fill="none" stroke="#123" stroke-width="3" '
                          'stroke-linecap="round" stroke-linejoin="round"/>'
                          '<path d="M3 22 L12 14 L21 22" fill="none" stroke="#f60" stroke-width="2" '
                          'stroke-linecap="square" stroke-linejoin="bevel"/>'), False),
    ("miter limit", svg('<path d="M2 20 L12 18 L22 20" fill="none" stroke="#000" stroke-width="3" stroke-miterlimit="12"/>'), False),
    ("transforms", svg('<g transform="translate(12 12) scale(0.8, 1.2)"><rect x="-6" y="-6" width="12" height="12" '
                       'fill="#e04" transform="skewX(15)"/></g><g transform="matrix(1 0 0 1 2 2)">'
                       '<circle cx="4" cy="4" r="2" transform="scale(1.5)"/></g>'), True),
    ("rotate about", svg('<rect x="8" y="4" width="8" height="16" fill="#08f" transform="rotate(30 12 12)"/>'
                         '<rect x="10" y="10" width="4" height="4" transform="rotate(-45)" fill="#f80"/>'), True),
    ("nested groups", svg('<g fill="#f00" stroke="#00f" stroke-width="2" opacity="0.6"><g fill="#0f0" opacity="0.5">'
                          '<circle cx="8" cy="12" r="6"/></g><rect x="13" y="6" width="9" height="12" stroke="none"/></g>'), False),
    ("style overrides", svg('<rect x="2" y="2" width="20" height="20" fill="red" style="fill: #0c0 ; stroke:#000;'
                            'stroke-width:2px;opacity:.75"/><circle cx="12" cy="12" r="5" fill="blue" '
                            'style="fill:yellow !important"/>'), False),
    ("current colour", svg('<path d="M4 4h16v16H4z" fill="currentColor" fill-opacity="0.5"/>'
                           '<path d="M6 12h12" stroke="currentColor" stroke-width="2" fill="none"/>'), False),
    ("colours", svg('<rect width="6" height="6" fill="#f0a"/><rect x="6" width="6" height="6" fill="#f0a8"/>'
                    '<rect x="12" width="6" height="6" fill="rgb(10%, 50%, 255)"/>'
                    '<rect x="18" width="6" height="6" fill="rgba(200,100,0,0.4)"/>'
                    '<rect y="6" width="6" height="6" fill="#11223380"/><rect x="6" y="6" width="6" height="6" fill="Teal"/>'
                    '<rect x="12" y="6" width="6" height="6" fill="url(#missing) orange"/>'
                    '<rect x="18" y="6" width="6" height="6" fill="url(#missing)" stroke="#000"/>'
                    '<rect y="12" width="6" height="6" fill="nonsense"/><rect x="6" y="12" width="6" height="6" fill="transparent" stroke="red"/>'), False),
    ("fill rules", svg('<path d="M12 2 L18 20 L3 8 L21 8 L6 20 Z" fill="#000" fill-rule="evenodd"/>', 'viewBox="0 0 24 24"'), False),
    ("display none", svg('<g display="none"><rect width="24" height="24"/></g><rect x="4" y="4" width="8" height="8" '
                         'style="display:none"/><rect x="12" y="12" width="8" height="8" fill="#0af"/>'), False),
    ("skipped content", '<?xml version="1.0"?><!DOCTYPE svg><!-- a comment <rect/> -->'
                        + svg('<defs><rect id="r" width="24" height="24"/></defs><title>x</title><desc>y</desc>'
                              '<linearGradient id="g"><stop offset="0"/></linearGradient>'
                              '<style><![CDATA[ rect { fill: red } ]]></style>'
                              '<circle cx="12" cy="12" r="8" fill="#a0f"/><unknown><rect x="1" y="1" width="4" height="4"/></unknown>'), False),
    ("viewBox offset", svg('<circle cx="0" cy="0" r="10" fill="#fa0"/>', 'viewBox="-12 -12 24 24"'), False),
    ("wide viewBox", svg('<rect width="48" height="16" fill="#08a"/>', 'viewBox="0 0 48 16"'), False),
    ("width height only", svg('<rect width="20" height="10" fill="#a08"/>', 'width="20px" height="10"'), False),
    ("no size", svg('<rect width="300" height="150" fill="#555"/><circle cx="150" cy="75" r="60" fill="#fff"/>', ''), False),
    ("path error stops", svg('<path d="M2 2 L22 2 L22 22 L x 2 2" fill="#000"/><path d="M2 22 L12 12 Z Q" stroke="#f00" fill="none"/>'), False),
    ("linear default", svg('<defs><linearGradient id="g"><stop offset="0" stop-color="#f00"/>'
                            '<stop offset="1" stop-color="#00f"/></linearGradient></defs>'
                            '<rect x="2" y="4" width="20" height="16" fill="url(#g)"/>'), False),
    ("linear user space", svg('<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="10%" y1="0" x2="90%" '
                              'y2="24" spreadMethod="reflect" gradientTransform="rotate(20 12 12)">'
                              '<stop offset="0%" stop-color="#0a0"/><stop offset="50%" stop-color="#ff0" '
                              'stop-opacity=".5"/><stop offset="100%" style="stop-color: #a00"/></linearGradient>'
                              '<path d="M2 2h20v20H2z" fill="url(#g)"/>'), True),
    ("linear repeat", svg('<linearGradient id="g" x1="0" y1="0" x2="0.25" y2="0.25" spreadMethod="repeat">'
                          '<stop offset=".2" stop-color="#000"/><stop offset=".8" stop-color="#fff"/></linearGradient>'
                          '<rect x="3" y="3" width="18" height="18" fill="url(#g)" stroke="#000"/>'), False),
    ("radial default", svg('<radialGradient id="r"><stop offset="0" stop-color="#fff"/><stop offset="1" '
                           'stop-color="#048"/></radialGradient><circle cx="12" cy="12" r="10" fill="url(#r)"/>'), True),
    ("radial focal", svg('<radialGradient id="r" cx="0.5" cy="0.5" r="0.5" fx="0.3" fy="0.3" fr="0.05">'
                         '<stop offset="0" stop-color="#ff8"/><stop offset="0.6" stop-color="#f80"/>'
                         '<stop offset="1" stop-color="#800"/></radialGradient>'
                         '<rect x="2" y="2" width="20" height="20" rx="4" fill="url(#r)"/>'), True),
    ("radial user space", svg('<radialGradient id="r" gradientUnits="userSpaceOnUse" cx="12" cy="12" r="40%" '
                              'spreadMethod="repeat"><stop offset="0" stop-color="#00f"/><stop offset="1" '
                              'stop-color="#0ff"/></radialGradient><path d="M2 12 L12 2 L22 12 L12 22Z" '
                              'fill="url(#r)"/>'), False),
    ("href chain", svg('<linearGradient id="base"><stop offset="0" stop-color="#f0f"/><stop offset=".5" '
                       'stop-color="#ff0"/><stop offset="1" stop-color="#0ff"/></linearGradient>'
                       '<linearGradient id="mid" href="#base" x2="0" y2="1"/>'
                       '<linearGradient id="top" xlink:href="#mid" spreadMethod="reflect" y2="0.5"/>'
                       '<radialGradient id="rad" href="#base" r="0.3"/>'
                       '<rect x="1" y="1" width="10" height="22" fill="url(#top)"/>'
                       '<rect x="13" y="1" width="10" height="22" fill="url(#rad)"/>',
                       'viewBox="0 0 24 24" xmlns:xlink="http://www.w3.org/1999/xlink"'), False),
    ("stops edge cases", svg('<linearGradient id="one"><stop offset=".5" stop-color="#e40"/></linearGradient>'
                             '<linearGradient id="none"/>'
                             '<linearGradient id="odd"><stop offset=".7" stop-color="#00f"/><stop offset=".2" '
                             'stop-color="#f00"/><stop offset="2" stop-color="rgb(0,200,0)" stop-opacity="0.3"/>'
                             '</linearGradient>'
                             '<rect x="2" y="2" width="9" height="9" fill="url(#one)"/>'
                             '<rect x="13" y="2" width="9" height="9" fill="url(#none)" stroke="#000"/>'
                             '<rect x="2" y="13" width="20" height="9" fill="url(#odd)"/>'), False),
    ("stroke gradient", svg('<linearGradient id="g" x2="0" y2="1"><stop offset="0" stop-color="#f00"/>'
                            '<stop offset="1" stop-color="#00f"/></linearGradient>'
                            '<path d="M4 4 L20 4 L20 20 L4 20 Z" fill="#eee" stroke="url(#g)" stroke-width="3"/>'
                            '<path d="M4 12 H20" stroke="url(#g)" stroke-width="2"/>'), False),
    ("gradient opacity", svg('<linearGradient id="g"><stop offset="0" stop-color="#000"/><stop offset="1" '
                             'stop-color="#f80"/></linearGradient><g opacity=".7"><rect x="2" y="2" width="20" '
                             'height="20" fill="url(#g)" fill-opacity=".5" stroke="#000" stroke-width="1.5"/></g>'), False),
    ("forward + fallback", svg('<rect x="2" y="2" width="9" height="20" fill="url(&quot;#later&quot;)"/>'
                               '<rect x="13" y="2" width="9" height="9" fill="url(#missing) #0a0"/>'
                               '<rect x="13" y="13" width="9" height="9" fill="url(#missing)" stroke="#000"/>'
                               '<defs><linearGradient id="later" x2="0" y2="1"><stop offset="0" stop-color="#08f"/>'
                               '<stop offset="1" stop-color="#f08"/></linearGradient></defs>'), False),
    ("css illustrator", svg('<defs><style>.cls-1{fill:#e94;}.cls-2{fill:none;stroke:#333;stroke-width:2px;}'
                            '.cls-3{fill:#3a7}</style></defs><circle class="cls-1" cx="9" cy="9" r="7"/>'
                            '<rect class="cls-2" x="3" y="3" width="18" height="18"/>'
                            '<rect class="extra cls-3" x="12" y="12" width="9" height="9"/>'), True),
    ("css specificity", svg('<style>rect{fill:red} .a{fill:green} #x{fill:blue} rect.a{fill:#ff0} '
                            '.b{fill:#f0f} .c{fill:#0ff} *{stroke:#000}</style>'
                            '<rect x="1" y="1" width="6" height="6"/><rect class="a" x="9" y="1" width="6" height="6"/>'
                            '<rect id="x" class="a" x="17" y="1" width="6" height="6"/>'
                            '<circle class="a" cx="4" cy="12" r="3"/><circle class="b c" cx="12" cy="12" r="3"/>'
                            '<circle class="c b" cx="20" cy="12" r="3"/>'), True),
    ("css precedence", svg('<style>.p{fill:#08f;stroke:#f00}</style>'
                           '<rect class="p" fill="#000" x="2" y="2" width="9" height="20"/>'
                           '<rect class="p" style="fill:#0a0" stroke="#00f" x="13" y="2" width="9" height="20"/>'), False),
    ("css ignored", svg('<style>/* rect{fill:red} */ g rect{fill:red} rect:hover{fill:red} [fill]{fill:red} '
                        'g>rect{fill:red} @media screen { rect { fill: red } } @import "x.css"; '
                        'rect{fill:#2a6}</style><g><rect x="2" y="2" width="20" height="20" fill="#000"/></g>'), False),
    ("css groups", svg('<style>.grp{fill:#808;stroke:#000;stroke-width:1.5}</style><style>.thin{stroke-width:.5}'
                       '.hide{display:none}.half{opacity:.5}</style>'
                       '<g class="grp"><circle cx="7" cy="7" r="5"/><circle class="thin" cx="17" cy="7" r="5"/>'
                       '<rect class="hide" width="24" height="24"/><rect class="half" x="2" y="14" width="20" '
                       'height="8"/></g>'), True),
    ("css gradient", svg('<style>.g{fill:url(#lg)}</style><linearGradient id="lg"><stop offset="0" '
                         'stop-color="#fc0"/><stop offset="1" stop-color="#c06"/></linearGradient>'
                         '<rect class="g" x="2" y="2" width="20" height="20"/>'), False),
    ("use sprite", svg('<defs><symbol id="dot" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></symbol>'
                       '<symbol id="bar" viewBox="0 0 20 10"><rect x="1" y="1" width="18" height="8" rx="2"/>'
                       '</symbol></defs><use href="#dot" x="1" y="1" width="8" height="8" fill="#e33"/>'
                       '<use href="#dot" x="12" y="1" width="10" height="6" fill="#3a3"/>'
                       '<use href="#bar" x="2" y="12" width="20" height="10" fill="#36f"/>'
                       '<use href="#bar" x="2" y="12" fill="none" stroke="#000"/>'), True),
    ("use transform", svg('<path id="tri" d="M0 0 L6 0 L3 5 Z" fill="#f80"/>'
                          '<use xlink:href="#tri" x="8" y="2"/><use href="#tri" transform="rotate(30 12 12)" x="10" y="10"/>'
                          '<use href="#tri" transform="scale(1.5)" x="1" y="9" fill="#00f" opacity=".5"/>',
                          'viewBox="0 0 24 24" xmlns:xlink="http://www.w3.org/1999/xlink"'), True),
    ("use inherit", svg('<style>.u{stroke:#c0c;stroke-width:1.5}</style><defs><g id="pair"><circle cx="4" cy="4" r="3"/>'
                        '<rect x="9" y="1" width="6" height="6" fill="#0aa"/></g></defs>'
                        '<use href="#pair" fill="#fa0"/><use href="#pair" class="u" y="8"/>'
                        '<use href="#pair" style="fill:#08f" x="4" y="15"/>'), True),
    ("use nested", svg('<defs><circle id="c" cx="2" cy="2" r="2"/><g id="row"><use href="#c"/><use href="#c" x="5"/>'
                       '<use href="#c" x="10"/></g><g id="grid"><use href="#row"/><use href="#row" y="6"/></g></defs>'
                       '<use href="#grid" x="2" y="2" fill="#555"/><use href="#grid" x="6" y="13" fill="#a22"/>'), True),
    ("use edge cases", svg('<g id="loop"><rect width="2" height="2" fill="#000"/><use href="#loop" x="2" y="2"/></g>'
                           '<use id="self" href="#self" x="3"/><use href="#missing" fill="#f00"/><use href="nohash"/>'
                           '<use href="#grad"/><linearGradient id="grad"/><symbol id="s"><rect x="14" y="14" '
                           'width="6" height="6" fill="#0c0"/></symbol><use href="#s"/>'
                           '<use href=" #c2 " display="none"/><circle id=" c2 " cx="20" cy="4" r="3" fill="#06c"/>'
                           '<use href="#c2" x="-4" y="16"/>'), True),
    ("named colours", svg('<rect x="0" y="0" width="6" height="8" fill="rebeccapurple"/><rect x="6" y="0" width="6" height="8" fill="CornflowerBlue"/><rect x="12" y="0" width="6" height="8" fill="darkSlateGrey"/><rect x="18" y="0" width="6" height="8" fill="papayawhip"/><rect x="0" y="8" width="6" height="8" fill="lightgoldenrodyellow"/><rect x="6" y="8" width="6" height="8" fill="tomato"/><rect x="12" y="8" width="6" height="8" fill="mediumspringgreen"/><rect x="18" y="8" width="6" height="8" fill="blueviolet"/><rect x="0" y="16" width="6" height="8" fill="Peru"/><rect x="6" y="16" width="6" height="8" fill="navajowhite"/><rect x="12" y="16" width="6" height="8" fill="firebrick"/><rect x="18" y="16" width="6" height="8" fill="olivedrab"/>'), False),
    ("hsl colours", svg('<rect x="0" y="0" width="6" height="8" fill="hsl(0, 100%, 50%)"/><rect x="6" y="0" width="6" height="8" fill="hsl(120deg 100% 25%)"/><rect x="12" y="0" width="6" height="8" fill="hsl(210, 60%, 70%)"/><rect x="18" y="0" width="6" height="8" fill="hsla(300, 50%, 50%, .5)"/><rect x="0" y="8" width="6" height="8" fill="hsl(-60 80% 40% / 75%)"/><rect x="6" y="8" width="6" height="8" fill="hsl(725, 40%, 55%)"/><rect x="12" y="8" width="6" height="8" fill="hsl(45, 0%, 30%)"/><rect x="18" y="8" width="6" height="8" fill="hsl(200 120% -5%)"/><rect x="0" y="16" width="6" height="8" fill="rgb(10 200 30 / .4)"/><rect x="6" y="16" width="6" height="8" fill="rgb(100% 50% 0% / 25%)"/><rect x="12" y="16" width="6" height="8" fill="hsl(30.5, 66.6%, 33.3%)"/><rect x="18" y="16" width="6" height="8" fill="HSL(90,100%,100%)"/>'), False),
    ("units", svg('<rect x="0.25in" y="2mm" width="12pt" height="1.5pc" fill="#c33"/>'
                  '<circle cx="1.6cm" cy="7.5px" r="0.25em" fill="#3c3"/><g font-size="8"><rect x="1em" y="2ex" '
                  'width="1.25em" height="1EM" fill="#33c" stroke="#000" stroke-width=".1em"/></g>'
                  '<line x1="1" y1="22" x2="23" y2="22" stroke="#880" stroke-width="2.4pt"/>'
                  '<rect x="3q" y="3" width="4" height="4"/><rect x="0" y="0" width="5zz" height="4"/>'), False),
    ("percent lengths", svg('<rect x="10%" y="25%" width="50%" height="12.5%" fill="#a5f"/>'
                            '<circle cx="75%" cy="75%" r="10%" fill="none" stroke="#063" stroke-width="2%"/>'
                            '<ellipse cx="25%" cy="80%" rx="20%" ry="5%" fill="#e90"/>', 'viewBox="0 0 40 20"'), False),
    ("font sizes", svg('<g font-size="x-small"><rect width="1em" height="1em" fill="#f00"/>'
                       '<g style="font-size:larger"><rect x="12" width="1em" height="1em" fill="#0a0"/>'
                       '<g font-size="150%"><rect y="12" width="1em" height="0.5em" fill="#00f"/></g></g>'
                       '<g font-size="smaller"><rect x="12" y="12" width="1em" height="1em" fill="#0aa"/></g>'
                       '<g font-size="xx-large" class="f"><rect x="20" y="20" width=".1em" height=".1em"/></g></g>'
                       '<style>.f{font-size:0.25in}</style>', 'viewBox="0 0 24 24"'), False),
    ("root units", svg('<rect width="12" height="12" fill="#246"/><rect x="12" y="12" width="12" height="12" fill="#642"/>',
                       'width="2em" height="1.5em"'), False),
    ("root percent", svg('<rect width="50%" height="50%" fill="#246"/>', 'width="100%" height="50%"'), False),
    ("inherit", svg('<g fill="#c00" stroke="#00c" stroke-width="2" opacity=".5"><g fill="#0c0" stroke-width="4">'
                    '<rect x="2" y="2" width="8" height="8" fill="inherit" style="stroke-width:inherit"/>'
                    '<rect x="14" y="2" width="8" height="8" style="fill:inherit" opacity="inherit"/>'
                    '<circle cx="6" cy="17" r="4" stroke="inherit" stroke-linecap="inherit" fill="#ff0"/></g>'
                    '<g style="fill:#0cc"><rect x="13" y="13" width="8" height="8" fill="red" style="fill: inherit !important"/>'
                    '</g></g>'), False),
    ("color property", svg('<g color="#d40"><rect x="1" y="1" width="10" height="10" fill="currentColor"/>'
                           '<g style="color:hsl(120,100%,30%)"><circle cx="17" cy="6" r="4" fill="none" '
                           'stroke="currentColor" stroke-width="2"/></g><rect x="1" y="13" width="10" height="10" '
                           'color="rgba(0,0,255,.5)" fill="currentColor"/><g color="currentColor">'
                           '<rect x="13" y="13" width="10" height="10" fill="currentColor"/></g></g>'), False),
    ("visibility", svg('<g visibility="hidden"><rect width="10" height="10" fill="#f00"/>'
                       '<rect x="12" width="10" height="10" visibility="visible" fill="#0a0"/>'
                       '<g style="visibility:collapse"><circle cx="5" cy="18" r="4"/></g></g>'
                       '<rect x="12" y="12" width="10" height="10" fill="#00f" visibility="bogus"/>'), False),
    ("paint order", svg('<g stroke="#000" stroke-width="4" fill="#fc0"><rect x="3" y="3" width="8" height="8" '
                        'paint-order="stroke"/><rect x="14" y="3" width="8" height="8" paint-order="markers stroke fill"/>'
                        '<rect x="3" y="14" width="8" height="8" style="paint-order:fill stroke"/>'
                        '<rect x="14" y="14" width="8" height="8" paint-order="stroke bogus"/></g>'), False),
    ("dashes", svg('<g fill="none" stroke="#039" stroke-width="2"><path d="M2 3H22" stroke-dasharray="4 2"/>'
                   '<path d="M2 7H22" stroke-dasharray="3" stroke-dashoffset="1.5"/>'
                   '<path d="M2 11H22" stroke-dasharray="1,2,3"/><circle cx="8" cy="18" r="4" '
                   'stroke-dasharray="25%" stroke-linecap="round"/><path d="M14 15H22" stroke-dasharray="0 0"/>'
                   '<path d="M14 18H22" stroke-dasharray="2 -1"/><path d="M14 21H22" stroke-dasharray=".5em 1x" '
                   'font-size="4"/><g stroke-dasharray="2 1"><path d="M2 23H12" stroke-dasharray="none"/>'
                   '<path d="M14 23.5H22" stroke-dashoffset="-1"/></g></g>'), False),
    ("switch", svg('<switch><rect width="10" height="10" fill="#f00" requiredExtensions="http://x"/>'
                   '<desc>skipped</desc><rect width="10" height="10" fill="#0a0" systemLanguage="fr, en-GB"/>'
                   '<rect width="10" height="10" fill="#00f"/></switch>'
                   '<switch><foreignObject width="10" height="10" requiredExtensions="http://www.w3.org/1999/xhtml"/>'
                   '<text>fallback</text><rect x="12" width="10" height="10" fill="#f0f"/></switch>'
                   '<switch><g systemLanguage="de"><circle cx="5" cy="17" r="4" fill="#f00"/></g>'
                   '<g systemLanguage=" EN "><circle cx="5" cy="17" r="4" fill="#0aa"/></g></switch>'
                   '<rect x="12" y="12" width="10" height="10" fill="#880" systemLanguage="en-US"/>'
                   '<rect x="12" y="12" width="5" height="5" fill="#f00" systemLanguage="eng"/>'
                   '<rect x="17" y="17" width="5" height="5" fill="#f00" requiredExtensions=""/>'), False),
    ("aspect ratio", svg('<defs><symbol id="w" viewBox="0 0 20 10"><rect width="20" height="10" fill="#38c"/>'
                         '<circle cx="10" cy="5" r="5" fill="#fd0"/></symbol></defs>'
                         '<use href="#w" width="10" height="10"/>'
                         '<use href="#w" x="12" width="10" height="10" preserveAspectRatio="none"/>'
                         '<use href="#w" y="12" width="10" height="10" preserveAspectRatio="xMinYMax"/>'
                         '<use href="#w" x="12" y="12" width="10" height="10" preserveAspectRatio="defer xMaxYMin meet"/>'
                         '<use href="#w" x="14" y="14" width="2" height="4" preserveAspectRatio="xMidYMid slice"/>'
                         '<use href="#w" x="2" y="20" width="3" height="3" preserveAspectRatio="xMinYMin bogus"/>'), False),
    ("nested svg", svg('<svg x="2" y="2" width="10" height="10" viewBox="0 0 100 100"><rect width="100" height="100" '
                       'fill="#e44"/><rect x="25%" y="25%" width="50%" height="50%" fill="#fff"/></svg>'
                       '<svg x="12" y="2" width="10" height="5" viewBox="0 0 10 10" preserveAspectRatio="xMaxYMid">'
                       '<circle cx="5" cy="5" r="5" fill="#4a4"/></svg><svg y="12" width="50%" height="50%">'
                       '<rect width="50%" height="50%" fill="#44e"/><svg x="12" width="0" height="5"><rect width="9" '
                       'height="9"/></svg></svg><svg x="14" y="14" width="8" height="8" viewBox="0 0 4 2" '
                       'preserveAspectRatio="none"><rect width="2" height="2" fill="#a0a"/><rect x="2" width="2" '
                       'height="2" fill="#0aa"/></svg>'), False),
    ("root aspect", svg('<rect width="24" height="24" fill="#357"/><circle cx="12" cy="12" r="10" fill="#fa3"/>',
                        'viewBox="0 0 24 24" width="48" height="24"'), False),
    ("root par none", svg('<rect width="24" height="12" fill="#357"/><circle cx="12" cy="12" r="10" fill="#fa3"/>',
                          'viewBox="0 0 24 24" width="40" height="20" preserveAspectRatio="none"'), False),
    ("root par align", svg('<rect width="24" height="12" fill="#753"/><circle cx="12" cy="12" r="10" fill="#3af"/>',
                           'viewBox="0 0 24 12" preserveAspectRatio="xMinYMax meet"'), False),
    ("root par slice", svg('<rect width="24" height="12" fill="#753"/><circle cx="12" cy="6" r="6" fill="#3af"/>',
                           'viewBox="0 0 24 12" width="10" height="20" preserveAspectRatio="xMaxYMin slice"'), False),
    ("group opacity", svg('<g opacity=".5"><rect x="2" y="2" width="12" height="12" fill="#c00"/>'
                          '<rect x="8" y="8" width="12" height="12" fill="#00c"/><g opacity=".6">'
                          '<circle cx="18" cy="6" r="5" fill="#0a0"/><circle cx="20" cy="9" r="4" fill="#aa0"/></g></g>'
                          '<rect x="2" y="16" width="8" height="6" fill="#0cc" stroke="#000" stroke-width="2" '
                          'opacity=".5"/><rect x="13" y="16" width="8" height="6" fill="#c0c" opacity=".5"/>'
                          '<use href="#u" x="1" y="1" opacity="0.4"/><g id="u" opacity="1">'
                          '<circle cx="4" cy="20" r="2" fill="#000"/><circle cx="5" cy="21" r="2" fill="#fff"/></g>'), False),
    ("opacity svg", svg('<svg opacity=".7" width="24" height="24"><rect width="16" height="16" fill="#e70"/>'
                        '<rect x="8" y="8" width="16" height="16" fill="#07e"/></svg><g opacity="0">'
                        '<rect width="24" height="24"/></g><g style="opacity:50%" stroke="#000" stroke-width="3">'
                        '<path d="M2 22L22 12" fill="none"/><path d="M2 12L22 22" fill="none"/></g>'), False),
    ("clip path", svg('<defs><clipPath id="c"><circle cx="12" cy="12" r="9"/><rect x="2" y="2" width="6" height="6" '
                      'transform="rotate(10 5 5)"/></clipPath></defs><g clip-path="url(#c)"><rect width="24" height="12" '
                      'fill="#d33"/><rect y="12" width="24" height="12" fill="#33d"/></g>'
                      '<rect x="16" y="16" width="8" height="8" fill="#0a0" clip-path="url(#c)" opacity=".7" '
                      'stroke="#000"/>'), True),
    ("clip rules", svg('<clipPath id="star" clip-rule="evenodd"><path d="M12 1L19 22L1 8H23L5 22Z"/></clipPath>'
                       '<clipPath id="nz"><path d="M12 1L19 22L1 8H23L5 22Z" style="clip-rule:nonzero"/></clipPath>'
                       '<rect width="12" height="24" fill="#f80" clip-path="url(#star)"/>'
                       '<rect x="12" width="12" height="24" fill="#08f" clip-path="url(#nz)"/>'), False),
    ("clip bbox units", svg('<clipPath id="o" clipPathUnits="objectBoundingBox"><circle cx=".5" cy=".5" r=".5"/>'
                            '</clipPath><rect x="2" y="2" width="20" height="10" fill="#a0a" clip-path="url(#o)"/>'
                            '<g clip-path="url(#o)" transform="translate(0 12)"><rect x="4" width="6" height="10" '
                            'fill="#0aa"/><rect x="14" y="2" width="6" height="8" fill="#aa0"/></g>'
                            '<g clip-path="url(#o)"><rect width="0" height="5"/></g>'), True),
    ("clip chained", svg('<clipPath id="a"><rect x="2" y="2" width="14" height="20"/></clipPath>'
                         '<clipPath id="b" clip-path="url(#a)"><circle cx="12" cy="12" r="10"/></clipPath>'
                         '<clipPath id="self" clip-path="url(#self)"><rect width="24" height="4"/></clipPath>'
                         '<rect width="24" height="24" fill="#5b5" clip-path="url(#b)"/>'
                         '<rect y="20" width="24" height="4" fill="#b55" clip-path="url(#self)"/>'), True),
    ("clip content", svg('<defs><path id="tri" d="M0 0L8 0L4 7Z"/></defs><clipPath id="u" transform="translate(2 2)">'
                         '<use href="#tri"/><use href="#tri" x="10"/><rect x="0" y="12" width="20" height="4" '
                         'display="none"/><rect x="0" y="12" width="20" height="4" visibility="hidden"/>'
                         '<rect x="0" y="18" width="20" height="3" fill="none"/></clipPath>'
                         '<rect width="24" height="24" fill="#333" clip-path="url(#u)"/>'
                         '<rect width="4" height="4" fill="#f00" clip-path="url(#tri)"/>'
                         '<rect x="20" width="4" height="4" fill="#0f0" clip-path="url(#nothing)"/>'
                         '<rect x="20" y="20" width="4" height="4" fill="#00f" style="clip-path:none" '
                         'clip-path="url(#u)"/>'), False),
    ("viewport clips", svg('<symbol id="s" viewBox="0 0 10 10"><circle cx="5" cy="5" r="8" fill="#e60"/></symbol>'
                           '<use href="#s" width="10" height="10"/><use href="#s" x="12" width="10" height="6"/>'
                           '<svg x="2" y="12" width="8" height="8"><rect x="-4" y="-4" width="20" height="20" '
                           'fill="#06e"/></svg><svg x="12" y="12" width="10" height="10" viewBox="0 0 4 4" '
                           'preserveAspectRatio="xMidYMid slice"><rect width="4" height="4" fill="#6c6"/>'
                           '<circle cx="2" cy="2" r="3" fill="none" stroke="#000"/></svg>'), True),
    ("root slice clip", svg('<rect x="-5" y="-5" width="40" height="40" fill="#357"/><circle cx="12" cy="6" r="7" '
                            'fill="#fa3"/>', 'viewBox="0 0 24 12" preserveAspectRatio="xMidYMid slice"'), False),
    ("root slice sized", svg('<rect x="-5" y="-5" width="40" height="40" fill="#753"/><circle cx="12" cy="6" r="7" '
                             'fill="#3af"/>', 'viewBox="0 0 24 12" width="10" height="20" '
                             'preserveAspectRatio="xMaxYMin slice"'), False),
    ("mask luminance", svg('<defs><linearGradient id="g"><stop offset="0" stop-color="#fff"/><stop offset="1" '
                           'stop-color="#000"/></linearGradient><mask id="m"><rect width="24" height="24" fill="url(#g)"/>'
                           '</mask></defs><g mask="url(#m)"><rect width="24" height="12" fill="#d22"/>'
                           '<rect y="12" width="24" height="12" fill="#22d"/></g>'), False),
    ("mask units", svg('<mask id="obb" maskContentUnits="objectBoundingBox"><circle cx=".5" cy=".5" r=".4" fill="#fff"/>'
                       '</mask><mask id="user" maskUnits="userSpaceOnUse" x="12" y="0" width="6" height="24">'
                       '<rect width="24" height="24" fill="white"/></mask>'
                       '<rect x="2" y="2" width="20" height="9" fill="#0a5" mask="url(#obb)"/>'
                       '<rect y="13" width="24" height="9" fill="#a50" stroke="#000" mask="url(#user)" opacity=".8"/>'),
     True),
    ("mask alpha", svg('<mask id="a" style="mask-type:luminance" mask-type="alpha" x="0" y="0" width="1" height="1">'
                       '<circle cx="12" cy="12" r="10" fill="#000" fill-opacity=".6"/></mask>'
                       '<mask id="l" x="0" y="0" width="1" height="1"><circle cx="12" cy="12" r="10" fill="#000" '
                       'fill-opacity=".6"/></mask><rect width="12" height="24" fill="#c0c" mask="url(#a)"/>'
                       '<rect x="12" width="12" height="24" fill="#c0c" mask="url(#l)"/>'), True),
    ("mask nested", svg('<mask id="inner"><rect width="24" height="12" fill="#fff"/></mask>'
                        '<mask id="outer" maskUnits="userSpaceOnUse" x="0" y="0" width="24" height="24">'
                        '<g mask="url(#inner)"><circle cx="12" cy="12" r="10" fill="#ccc"/></g></mask>'
                        '<mask id="self"><rect width="24" height="24" fill="#fff" mask="url(#self)"/></mask>'
                        '<g mask="url(#outer)" clip-path="url(#cp)"><rect width="24" height="24" fill="#26e"/></g>'
                        '<clipPath id="cp"><rect x="2" width="20" height="24"/></clipPath>'
                        '<rect x="4" y="18" width="16" height="4" fill="#e62" mask="url(#self)"/>'
                        '<rect x="4" y="14" width="2" height="2" mask="url(#cp)"/>'), True),
    ("pattern basic", svg('<defs><pattern id="ch" width="6" height="6" patternUnits="userSpaceOnUse">'
                          '<rect width="3" height="3" fill="#222"/><rect x="3" y="3" width="3" height="3" fill="#222"/>'
                          '</pattern></defs><rect x="1" y="1" width="22" height="10" fill="url(#ch) #f00"/>'
                          '<circle cx="12" cy="17" r="6" fill="url(#ch)" fill-opacity=".6"/>'), False),
    ("pattern bbox", svg('<pattern id="d" width=".25" height=".5"><circle cx="2" cy="2" r="1.5" fill="#06c"/>'
                         '</pattern><pattern id="c" width="25%" height="50%" patternContentUnits="objectBoundingBox">'
                         '<rect width=".2" height=".3" fill="#c60"/></pattern>'
                         '<rect x="2" y="2" width="16" height="8" fill="url(#d)" stroke="#000" stroke-width=".5"/>'
                         '<rect x="4" y="13" width="16" height="9" fill="url(#c)"/>'), False),
    ("pattern transform", svg('<pattern id="s" width="4" height="4" patternUnits="userSpaceOnUse" '
                              'patternTransform="rotate(30) scale(1.5)"><rect width="2" height="4" fill="#3a3"/>'
                              '</pattern><pattern id="v" width="8" height="8" patternUnits="userSpaceOnUse" '
                              'viewBox="0 0 2 2" preserveAspectRatio="none"><circle cx="1" cy="1" r=".8" fill="#a3a"/>'
                              '</pattern><path d="M2 2H22V12H2Z" fill="url(#s)" transform="translate(0 .5)"/>'
                              '<rect x="2" y="14" width="20" height="8" fill="url(#v)" opacity=".8"/>'), True),
    ("pattern stroke", svg('<pattern id="st" width="2" height="2" patternUnits="userSpaceOnUse">'
                           '<rect width="1" height="2" fill="#e33"/><rect x="1" width="1" height="2" fill="#33e"/>'
                           '</pattern><circle cx="12" cy="12" r="8" fill="none" stroke="url(#st)" stroke-width="4" '
                           'stroke-dasharray="6 2"/>'), False),
    ("pattern href", svg('<pattern id="base" width="6" height="6" patternUnits="userSpaceOnUse">'
                         '<circle cx="3" cy="3" r="2" fill="#0aa"/></pattern>'
                         '<pattern id="moved" href="#base" x="3" patternTransform="scale(.5)"/>'
                         '<pattern id="own" href="#base"><rect width="6" height="3" fill="#a0a"/></pattern>'
                         '<pattern id="loop" href="#loop" width="5" height="5" patternUnits="userSpaceOnUse"/>'
                         '<rect width="12" height="12" fill="url(#moved)"/><rect x="12" width="12" height="12" '
                         'fill="url(#own)"/><rect y="12" width="12" height="12" fill="url(#loop) #888"/>'
                         '<rect x="12" y="12" width="12" height="12" fill="url(#empty) #444"/>'), False),
    ("nested bases", svg('<clipPath id="cp"><rect width="6" height="6"/></clipPath>'
                         '<mask id="m"><g clip-path="url(#cp)" transform="translate(2 2)"><rect width="20" height="20" '
                         'fill="#fff"/></g></mask><pattern id="p" width="8" height="8" patternUnits="userSpaceOnUse">'
                         '<g clip-path="url(#cp)"><circle cx="4" cy="4" r="4" fill="#e80"/></g></pattern>'
                         '<g transform="translate(4 2)" mask="url(#m)"><rect width="12" height="12" fill="#08e"/></g>'
                         '<rect x="2" y="14" width="20" height="9" fill="url(#p)" transform="rotate(-5 12 18)"/>'), True),
    ("markers", svg('<defs><marker id="arrow" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="3" '
                    'markerHeight="3" orient="auto-start-reverse"><path d="M0 0L10 5L0 10Z" fill="#c00"/></marker>'
                    '<marker id="dot" markerWidth="2" markerHeight="2" refX="1" refY="1" markerUnits="userSpaceOnUse">'
                    '<circle cx="1" cy="1" r="1" fill="#06c"/></marker></defs>'
                    '<path d="M3 20L10 8L16 16L21 4" fill="none" stroke="#333" stroke-width="1.5" '
                    'marker-start="url(#arrow)" marker-mid="url(#dot)" marker-end="url(#arrow)"/>'), True),
    ("marker shapes", svg('<marker id="sq" markerWidth="4" markerHeight="4" refX="2" refY="2" orient="45" '
                          'markerUnits="userSpaceOnUse"><rect x="1" y="1" width="2" height="2" fill="#0a0"/></marker>'
                          '<marker id="big" markerWidth="2" markerHeight="2" refX="1" refY="1" overflow="visible">'
                          '<circle cx="1" cy="1" r="2" fill="#a0a" fill-opacity=".7"/></marker>'
                          '<polygon points="4,4 12,3 20,8 14,14" fill="none" stroke="#000" style="marker:url(#sq)"/>'
                          '<polyline points="3,20 8,16 13,21" fill="none" stroke="#000" marker-mid="url(#big)" '
                          'stroke-width="2"/><line x1="15" y1="20" x2="22" y2="17" marker-end="url(#sq)"/>'
                          '<g marker-start="url(#sq)"><path d="M18 2Q22 2 22 6" fill="none" stroke="#048" '
                          'marker-start="none"/></g>'), True),
    ("marker curves", svg('<marker id="tick" markerWidth="1" markerHeight="4" refX=".5" refY="2" orient="auto">'
                          '<rect width="1" height="4" fill="#e60"/></marker>'
                          '<path d="M2 6C6 0 10 12 14 6S22 2 22 8M3 14h8v6h-8z M14 14Q18 22 22 14" fill="#fec" '
                          'stroke="#444" marker-start="url(#tick)" marker-mid="url(#tick)" marker-end="url(#tick)" '
                          'opacity=".8"/>'), True),
    ("image fit", svg(f'<image x="1" y="1" width="10" height="10" href="{IMG}"/>'
                      f'<image x="13" y="1" width="10" height="10" preserveAspectRatio="none" xlink:href="{IMG}"/>'
                      f'<image x="1" y="13" width="10" height="10" preserveAspectRatio="xMinYMax slice" href="{IMG}"/>'
                      f'<image x="13" y="13" href="{IMG_PCT}" opacity=".6"/>',
                      'viewBox="0 0 24 24" xmlns:xlink="http://www.w3.org/1999/xlink"'), False),
    ("image clipped", svg(f'<clipPath id="o" clipPathUnits="objectBoundingBox"><circle cx=".5" cy=".5" r=".5"/>'
                          f'</clipPath><image width="24" height="16" href="{IMG}" clip-path="url(#o)" '
                          f'transform="rotate(8 12 8)"/><image y="16" width="8" height="8" href="photo.png"/>'
                          f'<image x="8" y="16" width="8" height="8" href="data:image/x-farbfeld;base64,AAAA"/>'
                          f'<image x="16" y="16" width="0" height="8" href="{IMG}"/>'), True),
    ("text basic", svg('<text x="1" y="7" font-size="5" fill="#036">Hi there</text>'
                       '<text x="12" y="14" font-size="4" text-anchor="middle" fill="#a30" stroke="#000" '
                       'stroke-width=".3">centre<tspan fill="#0a0" dy="2">down</tspan> back</text>'
                       '<text x="23" y="21" font-size="4" text-anchor="end" style="font-weight:bold" '
                       'letter-spacing="0.5" word-spacing="2">end it</text>'), False),
    ("text lists", svg('<text x="2 6 10" y="8" dx="0 1" dy="0 0 2" font-size="4">abcdef</text>'
                       '<text x="2" y="18" rotate="0 20 -20 45" font-size="5" fill="#609">wxyz</text>'
                       '<text x="14" y="18" font-size="3"><tspan x="14 16 18">pq</tspan><tspan y="23">rs</tspan></text>'),
     True),
    ("text spaces", svg('<text x="1" y="6" font-size="4">  a &amp; b\n   c  </text>'
                        '<text x="1" y="12" font-size="4" xml:space="preserve"> a  b</text>'
                        '<text x="1" y="18" font-size="4"><![CDATA[x<y]]>&#x41;&#66;&lt;\u00e9</text>'
                        '<text x="1" y="23" font-size="4">u<!-- c -->v<tspan> w </tspan> z</text>'), False),
    ("text styled", svg('<g opacity=".6"><text x="2" y="8" font-size="6" fill="url(#g)" font-weight="bolder" '
                        'clip-path="url(#c)">GRAD</text></g><linearGradient id="g"><stop offset="0" stop-color="#f00"/>'
                        '<stop offset="1" stop-color="#00f"/></linearGradient><clipPath id="c"><rect width="24" '
                        'height="6"/></clipPath><text x="2" y="18" font-size="5" fill="none" stroke="#080" '
                        'stroke-dasharray="1 .5">open<tspan opacity=".5" fill="#c0c" font-size="3">half</tspan></text>'
                        '<tspan x="2" y="22">alone</tspan>'), False),
    ("filter blur", svg('<filter id="b"><feGaussianBlur stdDeviation="1.5"/></filter>'
                        '<filter id="u" x="0" y="0" width="1" height="1" color-interpolation-filters="sRGB">'
                        '<feGaussianBlur stdDeviation="2 .5"/></filter>'
                        '<circle cx="7" cy="7" r="5" fill="#c33" filter="url(#b)"/>'
                        '<g filter="url(#u)" transform="translate(12 0)"><rect x="1" y="2" width="9" height="9" '
                        'fill="#36c"/></g><rect x="3" y="14" width="18" height="7" fill="#3a3" stroke="#000" '
                        'style="filter:url(#b)" opacity=".7"/>'), False),
    ("filter shadow", svg('<filter id="s" x="-20%" y="-20%" width="160%" height="160%"><feDropShadow dx="1.5" '
                          'dy="1" stdDeviation="1" flood-color="#000" flood-opacity=".6"/></filter>'
                          '<filter id="m"><feOffset in="SourceAlpha" dx="2" dy="2" result="o"/>'
                          '<feGaussianBlur in="o" stdDeviation="1" result="b"/><feMerge><feMergeNode in="b"/>'
                          '<feMergeNode in="SourceGraphic"/></feMerge></filter>'
                          '<rect x="3" y="3" width="8" height="8" rx="2" fill="#fa0" filter="url(#s)"/>'
                          '<circle cx="17" cy="16" r="5" fill="#0af" filter="url(#m)"/>'), False),
    ("filter color", svg('<filter id="g"><feColorMatrix type="saturate" values="0"/></filter>'
                         '<filter id="h"><feColorMatrix type="hueRotate" values="90"/></filter>'
                         '<filter id="t" color-interpolation-filters="sRGB"><feComponentTransfer>'
                         '<feFuncR type="table" tableValues="1 0"/><feFuncG type="discrete" tableValues="0 .5 1"/>'
                         '<feFuncB type="linear" slope=".5" intercept=".25"/></feComponentTransfer></filter>'
                         '<filter id="f" filterUnits="userSpaceOnUse" x="0" y="12" width="24" height="12">'
                         '<feFlood flood-color="#8c4" flood-opacity=".5" result="fl"/>'
                         '<feComposite in="SourceGraphic" in2="fl" operator="arithmetic" k2=".7" k3=".5"/>'
                         '<feBlend in2="fl" mode="multiply"/></filter>'
                         '<g fill="#e53"><rect x="1" y="1" width="6" height="10" filter="url(#g)"/>'
                         '<rect x="9" y="1" width="6" height="10" filter="url(#h)"/>'
                         '<rect x="17" y="1" width="6" height="10" filter="url(#t)"/>'
                         '<circle cx="12" cy="18" r="5" fill="#26d" filter="url(#f)"/></g>'), True),
    ("filter misc", svg('<filter id="mo" primitiveUnits="objectBoundingBox"><feMorphology operator="dilate" '
                        'radius=".08"/></filter><filter id="ti" x="0" y="0" width="1" height="1" primitiveUnits="userSpaceOnUse">'
                        '<feOffset dx="0" dy="0" x="13" y="2" width="3" height="4"/>'
                        '<feTile/></filter><filter id="un"><feTurbulence baseFrequency=".1"/></filter>'
                        '<path d="M3 3L10 6L4 10Z" fill="#555" filter="url(#mo)"/>'
                        '<g filter="url(#ti)"><rect x="13" y="2" width="2" height="2" fill="#a3c"/><rect x="15" y="4" width="1" height="2" fill="#3ac"/><rect x="21" y="10" width="1" height="1"/></g>'
                        '<rect x="2" y="14" width="8" height="8" fill="#000" filter="url(#un)"/>'
                        '<rect x="14" y="14" width="8" height="8" fill="#0a0" filter="url(#nothing)"/>'), False),
    ("attribute entities", svg('<linearGradient id="g&amp;1"><stop offset="0" stop-color="&#x23;ff0"/>'
                               '<stop offset="&#49;" stop-color="&#35;0&#x30;f"/></linearGradient>'
                               '<rect x="1" y="1" width="10" height="10" fill="&#35;0a0"/>'
                               '<path d="M13&#32;1&#x20;L23&#9;1L23 11z" fill="url(&#35;g&amp;1)"/>'
                               '<rect x="1" y="13" width="10" height="10" style="fill:#c00;stroke:&#x23;00f;'
                               'stroke-width:1&#46;5"/>'
                               '<g transform="translate(&#49;3 1&#51;)"><circle cx="5" cy="5" r="4" '
                               'fill="&#x72;gb(10, 90, 200)" opacity="&#48;.6"/></g>'), False),
    ("filter turbulence", svg('<filter id="fn" x="0" y="0" width="1" height="1"><feTurbulence type="fractalNoise" '
                              'baseFrequency=".15 .3" numOctaves="3" seed="7.8"/></filter>'
                              '<filter id="st" filterUnits="userSpaceOnUse" x="12" y="0" width="12" height="12" '
                              'color-interpolation-filters="sRGB"><feTurbulence baseFrequency=".21" numOctaves="2" '
                              'stitchTiles="stitch" seed="-3"/></filter>'
                              '<filter id="ob" primitiveUnits="objectBoundingBox"><feTurbulence baseFrequency="2.5" '
                              'x=".1" y=".1" width=".8" height=".8" stitchTiles="stitch"/>'
                              '<feComposite in2="SourceGraphic" operator="in"/></filter>'
                              '<rect width="11" height="11" filter="url(#fn)"/>'
                              '<rect x="12" width="12" height="12" filter="url(#st)"/>'
                              '<g transform="translate(2 13) scale(1.5 .9)"><circle cx="5" cy="5" r="5" fill="#f80" '
                              'filter="url(#ob)"/></g>'), False),
    ("filter convolve", svg('<filter id="em"><feConvolveMatrix order="3" kernelMatrix="-2 -1 0 -1 1 1 0 1 2"/></filter>'
                            '<filter id="bl"><feConvolveMatrix order="3 2" kernelMatrix="1 2 1 1 2 1" edgeMode="wrap" '
                            'preserveAlpha="true" bias=".1"/></filter>'
                            '<filter id="ed"><feConvolveMatrix order="2" kernelMatrix="1 -1 -1 1" divisor="0" '
                            'targetX="0" targetY="1" edgeMode="none"/></filter>'
                            '<filter id="bad"><feConvolveMatrix order="2.5" kernelMatrix="1 1 1 1"/></filter>'
                            '<filter id="cnt"><feConvolveMatrix kernelMatrix="1 1 1"/></filter>'
                            '<rect x="1" y="1" width="10" height="10" rx="3" fill="#3a6" stroke="#036" filter="url(#em)"/>'
                            '<circle cx="18" cy="6" r="5" fill="#c4a" fill-opacity=".7" filter="url(#bl)"/>'
                            '<path d="M2 14h8v8z" fill="#36f" filter="url(#ed)"/>'
                            '<rect x="13" y="13" width="4" height="9" fill="#a50" filter="url(#bad)"/>'
                            '<rect x="18" y="13" width="4" height="9" fill="#05a" filter="url(#cnt)"/>'), False),
    ("filter displace", svg('<filter id="d" x="-.2" y="-.2" width="1.4" height="1.4">'
                            '<feTurbulence baseFrequency=".2" numOctaves="2" result="n"/>'
                            '<feDisplacementMap in="SourceGraphic" in2="n" scale="4" xChannelSelector="R" '
                            'yChannelSelector="G"/></filter>'
                            '<filter id="o" primitiveUnits="objectBoundingBox"><feFlood flood-color="#80ff80" result="f"/>'
                            '<feDisplacementMap in="SourceGraphic" in2="f" scale=".3" xChannelSelector="B"/></filter>'
                            '<rect x="3" y="3" width="10" height="10" fill="#e33" stroke="#000" filter="url(#d)"/>'
                            '<circle cx="18" cy="17" r="5" fill="#33e" filter="url(#o)"/>'), False),
    ("filter lighting", svg('<filter id="di"><feGaussianBlur in="SourceAlpha" stdDeviation="1" result="b"/>'
                            '<feDiffuseLighting in="b" surfaceScale="4" diffuseConstant="1.1" lighting-color="#fec">'
                            '<feDistantLight azimuth="225" elevation="40"/></feDiffuseLighting>'
                            '<feComposite in2="SourceAlpha" operator="in"/></filter>'
                            '<filter id="sp"><feGaussianBlur in="SourceAlpha" stdDeviation="1.2" result="b"/>'
                            '<feSpecularLighting in="b" surfaceScale="3" specularConstant=".9" specularExponent="12">'
                            '<fePointLight x="15" y="2" z="8"/></feSpecularLighting>'
                            '<feComposite in2="SourceAlpha" operator="in" result="s"/>'
                            '<feMerge><feMergeNode in="SourceGraphic"/><feMergeNode in="s"/></feMerge></filter>'
                            '<filter id="cone" color-interpolation-filters="sRGB"><feDiffuseLighting surfaceScale="2" '
                            'lighting-color="#8cf"><feSpotLight x="2" y="14" z="10" pointsAtX="8" pointsAtY="20" '
                            'specularExponent="2" limitingConeAngle="-35"/><feDistantLight/></feDiffuseLighting></filter>'
                            '<filter id="ob" primitiveUnits="objectBoundingBox"><feSpecularLighting specularExponent="4" '
                            'surfaceScale="2"><fePointLight x=".2" y=".1" z=".5"/></feSpecularLighting></filter>'
                            '<filter id="dark"><feDiffuseLighting/></filter>'
                            '<rect x="1" y="1" width="9" height="9" rx="2" fill="#888" filter="url(#di)"/>'
                            '<circle cx="17" cy="6" r="5" fill="#a22" filter="url(#sp)"/>'
                            '<rect x="1" y="13" width="10" height="10" fill="#fff" fill-opacity=".8" filter="url(#cone)"/>'
                            '<g transform="translate(13 13) scale(.9 1.1)"><circle cx="4" cy="4" r="4" fill="#0a0" '
                            'filter="url(#ob)"/></g><rect x="20" y="20" width="3" height="3" filter="url(#dark)"/>'),
     True),
    ("filter image", svg(f'<filter id="i" x="0" y="0" width="1" height="1"><feImage href="{IMG}"/></filter>'
                         f'<filter id="n" x="0" y="0" width="1" height="1"><feImage xmlns:xlink="http://www.w3.org/1999/xlink" xlink:href="{IMG}" '
                         f'preserveAspectRatio="none" x="13" y="1" width="10" height="5"/></filter>'
                         f'<filter id="s" primitiveUnits="objectBoundingBox" color-interpolation-filters="linearRGB">'
                         f'<feImage href="{IMG_PCT}" preserveAspectRatio="xMaxYMax slice" result="im"/>'
                         f'<feComposite in="im" in2="SourceGraphic" operator="in"/></filter>'
                         f'<filter id="r"><feImage href="#none"/></filter>'
                         f'<rect x="1" y="1" width="10" height="10" fill="#eee" filter="url(#i)"/>'
                         f'<rect x="13" y="1" width="10" height="10" fill="#eee" filter="url(#n)"/>'
                         f'<circle cx="6" cy="18" r="5" fill="#000" filter="url(#s)"/>'
                         f'<rect x="14" y="14" width="8" height="8" filter="url(#r)"/>'), False),
    ("lucide style", svg('<path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>',
                         'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
                         'stroke-linejoin="round"'), True),
    ("material style", svg('<path d="M0 0h24v24H0z" fill="none"/><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 '
                           '10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z"/>'), False),
    ("fontawesome style", svg('<path d="M256 8C119 8 8 119 8 256s111 248 248 248 248-111 248-248S393 8 256 8zm0 448c-110.5 0-200-89.5-200-200S145.5 56 256 56s200 89.5 200 200-89.5 200-200 200z"/>',
                              'viewBox="0 0 512 512"'), True),
]


def run(tool, d, cmds):
    sp, raw = os.path.join(d, "s.bin"), os.path.join(d, "s.raw")
    open(sp, "wb").write(encode(cmds))
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    return (np.frombuffer(open(raw, "rb").read(), np.uint8).astype(int) if r.returncode == 0 else None), r.returncode


def svg_cmd(text, current, x, y, size):
    return ('svg', text.encode(), current, x, y, size)


def main():
    tool = os.path.abspath(sys.argv[1])
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_svg.") as d:
        blank, _ = run(tool, d, [])
        for name, text, trig in CASES:
            for current, (x, y, size) in ((0xFF2050C0, (8, 0, 32)), (0x80E0E020, (2, 3, 27.5))):
                total += 1
                got, rc = run(tool, d, [svg_cmd(text, current, x, y, size)])
                doc = svgmodel.parse(text, farbfeld, test_font)
                want, rc2 = run(tool, d, expected_calls(doc, current, x, y, size))
                if got is None or want is None:
                    print(f"FAIL  {name:20} exit {rc}/{rc2}")
                    failed += 1
                    continue
                diff = np.abs(got - want).reshape(-1, 4).max(axis=1)
                off = int((diff > 1).sum())
                exact = int(diff.max()) == 0
                ok = exact or (trig and off <= 3)
                painted = int((want != blank).reshape(-1, 4).any(axis=1).sum())
                failed += not ok
                print(f"{'ok  ' if ok else 'FAIL'}  {name:20} items={len(doc.items):2} max_diff={int(diff.max()):3d} "
                      f"pixels_off={off} painted={painted}")
        for name, text in (("not svg", "<html><body/></html>"), ("empty", ""), ("text only", "hello"),
                           ("too deep", "<svg>" + "<g>" * 70 + "</g>" * 70 + "</svg>")):
            total += 1
            _, rc = run(tool, d, [svg_cmd(text, 0xFF000000, 0, 0, 16)])
            ok = rc == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  refuse {name:16} exit={rc}")
        total += 1
        _, rc = run(tool, d, [svg_cmd('<svg viewBox="0 0 10 10"><rect width="5" height="5"/>', 0xFF000000, 0, 0, 16)])
        failed += rc != 0
        print(f"{'ok  ' if rc == 0 else 'FAIL'}  unterminated document kept   exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

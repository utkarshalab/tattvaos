#!/usr/bin/env python3
"""Convert SVG icons to a UIC pack (docs/UIC.md).

Library:
    icon, warnings = convert(svg_text, name, design_size=0)

Command line:
    svg2uic.py [--size N] [--prefix P] out.uic  file.svg | directory ...
        every .svg becomes an icon named prefix + its file name without
        .svg; --size marks them as pixel-tuned for N pixels

The SVG is read with tools/svgmodel.py (the same subset ugfx draws).
Transforms are baked into the coordinates (exact for lines and curves);
stroke widths scale by sqrt|det| (a non-uniform transform under a stroke
is reported, since UIC strokes cannot follow it). Colours become slots:
currentColor is slot 0; an icon with one colour and no currentColor gets
that colour in slot 0 so it can be recoloured; other colours follow in
order of use. Alpha from opacity becomes OPACITY commands, so a slot holds
one colour. UIC has no gradients: a gradient becomes the average of its
stop colours, with a warning. More than 16 colours, or coordinates beyond
what an i16 can hold, are errors.

Development-machine tooling only; not part of any OS image.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import svgmodel  # noqa: E402
from uic import Icon, pack  # noqa: E402


class ConvertError(Exception):
    pass


def apply(m, x, y):
    a, b, c, d, e, f = m
    return a * x + c * y + e, b * x + d * y + f


def ellipse(cx, cy, rx, ry):
    out = [('move', cx + rx, cy)]
    out += [('cubic', *p) for p in svgmodel.axis_arc(cx, cy, rx, ry, 0.0, 2 * math.pi)]
    return out + [('close',)]


def expand(path):
    """rect / circle / ellipse shorthands as lines and cubics."""
    out = []
    for c in path:
        if c[0] == 'rect':
            _, x, y, w, h = c
            out += [('move', x, y), ('line', x + w, y), ('line', x + w, y + h), ('line', x, y + h), ('close',)]
        elif c[0] == 'circle':
            out += ellipse(c[1], c[2], c[3], c[3])
        elif c[0] == 'ellipse':
            out += ellipse(*c[1:])
        else:
            out.append(c)
    return out


def transform(path, m):
    out = []
    for c in path:
        if c[0] == 'close':
            out.append(c)
            continue
        pts = [apply(m, c[k], c[k + 1]) for k in range(1, len(c), 2)]
        out.append((c[0], *(v for p in pts for v in p)))
    return out


def flatten(doc, warnings, name):
    """UIC has no layers: a group's opacity goes into each item inside it."""
    items, alphas = [], [255]
    for it in doc.items:
        if isinstance(it, svgmodel.MarkerItem):
            warnings.append(f"{name}: marker left out")
            continue
        if isinstance(it, svgmodel.Group):
            if it.kind == "begin":
                alphas.append(alphas[-1] * it.alpha // 255)
                warnings.append(f"{name}: group opacity applied per item")
            elif len(alphas) > 1:
                alphas.pop()
            continue
        a = alphas[-1]
        if a != 255:
            for attr in ("fill", "stroke"):
                p = getattr(it, attr)
                if p and p[0] == "paint":
                    setattr(it, attr, p[:6] + (int(p[6] * a / 255 + 0.5),))
                elif p:
                    setattr(it, attr, (p[0], int((p[1] >> 24) * a / 255 + 0.5) << 24 | (p[1] & 0xFFFFFF)))
        items.append(it)
    doc.items = items


def convert(text, name, design_size=0):
    doc = svgmodel.parse(text)
    warnings = []
    flatten(doc, warnings, name)
    for it in doc.items:
        for attr in ("fill", "stroke"):
            p = getattr(it, attr)
            if p and p[0] == "pattern":
                setattr(it, attr, None)
                warnings.append(f"{name}: pattern paint left out")
    for it in doc.items:
        for attr in ("fill", "stroke"):
            p = getattr(it, attr)
            if p and p[0] == "paint":
                stops, alpha = p[4], p[6]
                avg = [sum((c >> s) & 255 for _, c in stops) / len(stops) for s in (0, 8, 16, 24)]
                a = int(avg[3] * alpha / 255 + 0.5)
                rgb = sum(int(v + 0.5) << s for v, s in zip(avg[:3], (0, 8, 16)))
                setattr(it, attr, ("colour", a << 24 | rgb))
                warnings.append(f"{name}: gradient drawn as its average colour")
    vb = doc.viewbox
    w, h = doc.width, doc.height
    if vb is not None and w and w > 0 and h and h > 0:
        # the viewBox goes into width x height first: bake that in
        a = svgmodel.fit(vb, w, h, doc.par)
        for it in doc.items:
            it.matrix = svgmodel.mul(a, it.matrix)
        vb = [0.0, 0.0, w, h]
    elif vb is not None and doc.par != (5, 0) and vb[2] != vb[3]:
        # UIC centres its viewBox; a square of the larger side, with the
        # alignment baked in, maps the same way
        side = max(vb[2], vb[3])
        a = svgmodel.fit(vb, side, side, doc.par)
        for it in doc.items:
            it.matrix = svgmodel.mul(a, it.matrix)
        vb = [0.0, 0.0, side, side]
    if vb is None:
        vb = [0.0, 0.0, w if w and w > 0 else 300.0, h if h and h > 0 else 150.0]
    paints = [p for it in doc.items for p in (it.fill, it.stroke) if p]
    uses_current = any(p[0] == "current" for p in paints)
    rgbs = []
    for p in paints:
        if p[0] == "colour" and (p[1] & 0xFFFFFF) not in rgbs:
            rgbs.append(p[1] & 0xFFFFFF)
    if uses_current:
        slots = [0xFF000000] + [0xFF000000 | c for c in rgbs]
    elif rgbs:
        slots = [0xFF000000 | c for c in rgbs]
    else:
        slots = [0xFF000000]
    if len(slots) > 16:
        raise ConvertError(f"{name}: {len(slots)} colours, UIC holds 16")

    def slot_of(p):
        if p[0] == "current":
            return 0
        return slots.index(0xFF000000 | (p[1] & 0xFFFFFF))

    commands, alpha = [], 255
    for it in doc.items:
        path = transform(expand(it.path), it.matrix)
        a, b, c, d = it.matrix[:4]
        if it.dash:
            warnings.append(f"{name}: dashed stroke drawn solid")
        order = ((it.stroke, True), (it.fill, False)) if it.order else ((it.fill, False), (it.stroke, True))
        for paint, is_stroke in order:
            if not paint:
                continue
            want = paint[1] >> 24
            if want != alpha:
                commands.append(('opacity', want))
                alpha = want
            commands += path
            if is_stroke:
                scale = math.sqrt(abs(a * d - b * c))
                if abs((a * a + b * b) - (c * c + d * d)) > 1e-9 * (a * a + b * b + c * c + d * d) or \
                        abs(a * c + b * d) > 1e-9 * (a * a + b * b + c * c + d * d):
                    warnings.append(f"{name}: stroke under a non-uniform transform; width approximated")
                if it.miter != 4.0 and it.join == 0:
                    warnings.append(f"{name}: miter limit {it.miter:g} drawn as 4")
                commands.append(('stroke', slot_of(paint), it.join, it.cap, it.width * scale))
            else:
                commands.append(('fill', slot_of(paint), it.rule))
    icon = Icon(name, tuple(vb), slots, commands, design_size)
    # every coordinate must fit an i16 at 0 fraction bits at worst
    f = icon.fraction_bits()
    m = max([abs(v) for c in commands if c[0] in ('move', 'line', 'quad', 'cubic') for v in c[1:]] + [0.0])
    if round(m * (1 << f)) > 32767:
        raise ConvertError(f"{name}: coordinate {m:g} too large for UIC")
    return icon, warnings


def main(argv):
    size, prefix, args = 0, "", list(argv)
    while args and args[0].startswith("--"):
        opt = args.pop(0)
        if opt == "--size":
            size = int(args.pop(0))
        elif opt == "--prefix":
            prefix = args.pop(0)
        else:
            sys.exit(__doc__)
    if len(args) < 2:
        sys.exit(__doc__)
    out, inputs = args[0], []
    for a in args[1:]:
        if os.path.isdir(a):
            inputs += sorted(os.path.join(a, f) for f in os.listdir(a) if f.endswith(".svg"))
        else:
            inputs.append(a)
    icons, failed = [], 0
    for path in inputs:
        name = prefix + os.path.basename(path)[:-4]
        try:
            icon, warnings = convert(open(path, encoding="utf-8").read(), name, size)
        except Exception as e:      # report and continue with the rest
            print(f"skipped {path}: {e}", file=sys.stderr)
            failed += 1
            continue
        for w in warnings:
            print(f"warning: {w}", file=sys.stderr)
        icons.append(icon)
    data = pack(icons)
    open(out, "wb").write(data)
    print(f"{out}: {len(icons)} icons, {len(data)} bytes" + (f", {failed} skipped" if failed else ""))


if __name__ == "__main__":
    main(sys.argv[1:])

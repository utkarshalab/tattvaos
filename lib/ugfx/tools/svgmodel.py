#!/usr/bin/env python3
"""A model of the SVG subset 2d/svg.asm reads, following the same rules.

    doc = parse(text)        -> Doc(viewbox, width, height, items)
    item.matrix              element -> viewBox space (a b c d e f)
    item.path                path commands: ('move', x, y) ('line', x, y)
                             ('quad', ...) ('cubic', ...) ('close',)
                             ('rect', x, y, w, h) ('circle', cx, cy, r)
                             ('ellipse', cx, cy, rx, ry)
    item.fill / item.stroke  None, ('colour', 0xAARRGGBB) or ('current', alpha)
    item.rule, .width, .miter, .join, .cap

Used by tests/host/svg_check.py as the reference, and by the SVG -> UIC
converter. Development-machine tooling only; not part of any OS image.
"""
import math
import re
from dataclasses import dataclass, field

SKIP = {"defs", "clipPath", "mask", "symbol", "linearGradient", "radialGradient", "pattern", "marker", "text",
        "style", "script", "title", "desc", "metadata", "foreignObject", "filter"}
SHAPES = {"path", "rect", "circle", "ellipse", "line", "polyline", "polygon"}
PROPS = {"fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "fill-rule",
         "fill-opacity", "stroke-opacity", "opacity", "display"}
KEYWORDS = {"black": 0x000000, "white": 0xFFFFFF, "red": 0xFF0000, "lime": 0x00FF00, "green": 0x008000,
            "blue": 0x0000FF, "yellow": 0xFFFF00, "cyan": 0x00FFFF, "aqua": 0x00FFFF, "magenta": 0xFF00FF,
            "fuchsia": 0xFF00FF, "gray": 0x808080, "grey": 0x808080, "silver": 0xC0C0C0, "maroon": 0x800000,
            "olive": 0x808000, "navy": 0x000080, "purple": 0x800080, "teal": 0x008080, "orange": 0xFFA500}
NUMBER = re.compile(r"[ \t\r\n,]*([+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)")
SEP = re.compile(r"[ \t\r\n,]*")
WS = re.compile(r"[ \t\r\n]*")


@dataclass
class Item:
    matrix: list
    path: list
    fill: object
    stroke: object
    rule: int
    width: float
    miter: float
    join: int
    cap: int


@dataclass
class Doc:
    viewbox: object = None
    width: object = None
    height: object = None
    items: list = field(default_factory=list)


def number(s, i):
    """(value, next index) or (None, i), as ugfx_svg_number reads it."""
    m = NUMBER.match(s, i)
    if not m:
        return None, i
    return float(m.group(1)), m.end()


def mul(m1, m2):
    a1, b1, c1, d1, e1, f1 = m1
    a2, b2, c2, d2, e2, f2 = m2
    return [a1 * a2 + c1 * b2, b1 * a2 + d1 * b2, a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
            a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1]


DEG = 0.017453292519943295


def transform_list(s, m):
    """m x each transform; None if the list is invalid."""
    i = 0
    names = ("matrix", "translate", "scale", "rotate", "skewX", "skewY")
    while True:
        i = SEP.match(s, i).end()
        if i >= len(s):
            return m
        for name in names:
            if s[i:i + len(name)].lower() == name.lower():
                break
        else:
            return None
        i = WS.match(s, i + len(name)).end()
        if i >= len(s) or s[i] != '(':
            return None
        i += 1
        args = []
        while len(args) < 6:
            v, j = number(s, i)
            if v is None:
                break
            args.append(v)
            i = j
        i = SEP.match(s, i).end()
        if i >= len(s) or s[i] != ')':
            return None
        i += 1
        n = len(args)
        t = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        if name == "matrix":
            if n != 6:
                return None
            t = args
        elif name == "translate":
            if n not in (1, 2):
                return None
            t[4] = args[0]
            if n == 2:
                t[5] = args[1]
        elif name == "scale":
            if n not in (1, 2):
                return None
            t[0] = t[3] = args[0]
            if n == 2:
                t[3] = args[1]
        elif name == "rotate":
            if n not in (1, 3):
                return None
            if n == 3:
                m = mul(m, [1.0, 0.0, 0.0, 1.0, args[1], args[2]])
            a = args[0] * DEG
            m = mul(m, [math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0.0, 0.0])
            if n == 3:
                t = [1.0, 0.0, 0.0, 1.0, 0.0 - args[1], 0.0 - args[2]]
            else:
                continue
        else:
            if n != 1:
                return None
            tn = math.tan(args[0] * DEG)
            t = [1.0, 0.0, tn, 1.0, 0.0, 0.0] if name == "skewX" else [1.0, tn, 0.0, 1.0, 0.0, 0.0]
        m = mul(m, t)


def colour(s):
    """('none'|'colour'|'current'|'inherit'|None, 0xAARRGGBB)."""
    s = s.lstrip(" \t\r\n")
    low = s.lower()
    for word, kind in (("none", "none"), ("transparent", "none"), ("currentcolor", "current"),
                       ("inherit", "inherit")):
        if low.startswith(word):
            return kind, 0
    if low.startswith("url("):
        j = s.find(")")
        if j < 0:
            return "none", 0
        rest = s[j + 1:].lstrip(" \t\r\n")
        return colour(rest) if rest else ("none", 0)
    if low.startswith("rgba(") or low.startswith("rgb("):
        i = s.index("(") + 1
        vals = []
        while len(vals) < 4:
            v, j = number(s, i)
            if v is None:
                break
            i = j
            pct = i < len(s) and s[i] == '%'
            if pct:
                i += 1
            if len(vals) == 3:
                v = (v * 0.01 if pct else v) * 255.0
            elif pct:
                v = v * 0.01 * 255.0
            vals.append(int(min(max(v, 0.0), 255.0) + 0.5))
        i = SEP.match(s, i).end()
        if i >= len(s) or s[i] != ')' or len(vals) < 3:
            return None, 0
        a = vals[3] if len(vals) == 4 else 255
        return "colour", a << 24 | vals[0] << 16 | vals[1] << 8 | vals[2]
    if s.startswith("#"):
        digits = re.match(r"[0-9a-fA-F]{0,8}", s[1:]).group(0)
        n = len(digits)
        if n in (3, 4):
            v = [int(c, 16) * 17 for c in digits] + ([255] if n == 3 else [])
            return "colour", v[3] << 24 | v[0] << 16 | v[1] << 8 | v[2]
        if n == 6:
            return "colour", 0xFF000000 | int(digits, 16)
        if n == 8:
            v = int(digits, 16)
            return "colour", (v & 255) << 24 | v >> 8
        return None, 0
    for word, rgb in KEYWORDS.items():
        if low.startswith(word) and not (len(low) > len(word) and low[len(word)].isalpha()):
            return "colour", 0xFF000000 | rgb
    return None, 0


def arc_cubics(x1, y1, x2, y2, rx, ry, phi, large, sweep):
    """umath_arc_svg_to_cubics, in Python."""
    if x1 == x2 and y1 == y2:
        return []
    rx, ry = abs(rx), abs(ry)
    if rx == 0 or ry == 0:
        return [(x1, y1, x2, y2, x2, y2)]
    c, s = math.cos(phi), math.sin(phi)
    dx, dy = (x1 - x2) * 0.5, (y1 - y2) * 0.5
    xp, yp = c * dx + s * dy, c * dy - s * dx
    lam = (xp / rx) ** 2 + (yp / ry) ** 2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
        coef = 0.0
    else:
        num = rx * rx * ry * ry - (yp * yp) * (rx * rx) - (xp * xp) * (ry * ry)
        coef = math.sqrt(max(0.0, num / ((yp * yp) * (rx * rx) + (xp * xp) * (ry * ry))))
    if bool(large) == bool(sweep):
        coef = -coef
    cxp, cyp = rx * yp / ry * coef, -(ry * xp / rx * coef)
    cx = c * cxp - s * cyp + (x1 + x2) * 0.5
    cy = s * cxp + c * cyp + (y1 + y2) * 0.5
    ux, uy = (xp - cxp) / rx, (yp - cyp) / ry
    vx, vy = (-xp - cxp) / rx, (-yp - cyp) / ry
    t1 = math.atan2(uy, ux)
    dt = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    if sweep and dt < 0:
        dt += 2 * math.pi
    elif not sweep and dt > 0:
        dt -= 2 * math.pi
    out = []
    for p in axis_arc(0.0, 0.0, rx, ry, t1, dt):
        pts = [(c * p[k] - s * p[k + 1] + cx, s * p[k] + c * p[k + 1] + cy) for k in (0, 2, 4)]
        out.append(tuple(v for pt in pts for v in pt))
    if out:
        out[-1] = out[-1][:4] + (x2, y2)
    return out


def axis_arc(cx, cy, rx, ry, start, sweep):
    """umath_arc_to_cubics: n = ceil(|sweep| / (pi / 2)) pieces."""
    if sweep == 0 or sweep != sweep:
        return []
    sweep = max(-2 * math.pi, min(2 * math.pi, sweep))
    n = max(1, min(4, math.ceil(abs(sweep) / (math.pi / 2))))
    step = sweep / n
    k = 4.0 / 3.0 * math.tan(step / 4)
    out, a = [], start
    for _ in range(n):
        c0, s0, c1, s1 = math.cos(a), math.sin(a), math.cos(a + step), math.sin(a + step)
        out.append((cx + rx * (c0 - k * s0), cy + ry * (s0 + k * c0), cx + rx * (c1 + k * s1), cy + ry * (s1 - k * c1),
                    cx + rx * c1, cy + ry * s1))
        a += step
    return out


def path_data(d):
    """SVG path data -> commands, stopping at the first error."""
    out, i = [], 0
    cmd = prev = None
    cx = cy = sx = sy = lx = ly = 0.0
    counts = {'m': 2, 'l': 2, 'h': 1, 'v': 1, 'c': 6, 's': 4, 'q': 4, 't': 2, 'a': 7}
    while True:
        i = SEP.match(d, i).end()
        if i >= len(d):
            break
        ch = d[i]
        if ch in "zZ":
            i += 1
            cmd = prev = 'z'
            out.append(('close',))
            cx, cy = lx, ly = sx, sy
            continue
        if ch.lower() in counts:
            cmd = ch
            i += 1
        elif cmd is None or cmd == 'z':
            break
        elif cmd in "Mm":
            cmd = 'L' if cmd == 'M' else 'l'
        low = cmd.lower()
        args = []
        ok = True
        for k in range(counts[low]):
            if low == 'a' and k in (3, 4):
                i = SEP.match(d, i).end()
                if i >= len(d) or d[i] not in "01":
                    ok = False
                    break
                args.append(float(d[i]))
                i += 1
                continue
            v, j = number(d, i)
            if v is None:
                ok = False
                break
            args.append(v)
            i = j
        if not ok:
            break
        if cmd.islower():
            if low == 'h':
                args[0] += cx
            elif low == 'v':
                args[0] += cy
            elif low == 'a':
                args[5] += cx
                args[6] += cy
            else:
                for k in range(0, len(args), 2):
                    args[k] += cx
                    args[k + 1] += cy
        if low == 'm':
            sx, sy = args
            out.append(('move', *args))
            cx, cy = lx, ly = args
        elif low in 'lhv':
            x, y = (args[0], cy) if low == 'h' else (cx, args[0]) if low == 'v' else args
            out.append(('line', x, y))
            cx, cy = lx, ly = x, y
        elif low in 'cs':
            if low == 's':
                c1 = (2 * cx - lx, 2 * cy - ly) if prev in ('c', 's') else (cx, cy)
                args = [*c1, *args]
            out.append(('cubic', *args))
            lx, ly, cx, cy = args[2:6]
        elif low in 'qt':
            if low == 't':
                c1 = (2 * cx - lx, 2 * cy - ly) if prev in ('q', 't') else (cx, cy)
                args = [*c1, *args]
            out.append(('quad', *args))
            lx, ly, cx, cy = args
        else:
            for piece in arc_cubics(cx, cy, args[5], args[6], args[0], args[1], args[2] * DEG, args[3], args[4]):
                out.append(('cubic', *piece))
            cx, cy = lx, ly = args[5], args[6]
        prev = low
    return out


def points(s, close):
    out, i, vals = [], 0, []
    while True:
        v, i = number(s, i)
        if v is None:
            break
        vals.append(v)
    for k in range(0, len(vals) - 1, 2):
        out.append(('move' if not out else 'line', vals[k], vals[k + 1]))
    if close and out:
        out.append(('close',))
    return out


def rounded_rect(x, y, w, h, rx, ry):
    out = [('move', x + rx, y)]
    for corner in range(4):
        ccx = x + w - rx if corner < 2 else x + rx
        ccy = y + h - ry if corner in (1, 2) else y + ry
        start = corner * (math.pi / 2) + -(math.pi / 2)
        sx, sy = [(ccx, ccy - ry), (ccx + rx, ccy), (ccx, ccy + ry), (ccx - rx, ccy)][corner]
        out.append(('line', sx, sy))
        out += [('cubic', *p) for p in axis_arc(ccx, ccy, rx, ry, start, math.pi / 2)]
    return out + [('close',)]


def trim(v):
    v = v.strip(" \t\r\n")
    if len(v) >= 10 and v[-10] == '!':
        v = v[:-10].strip(" \t\r\n")
    return v


def parse(text):
    import xml.etree.ElementTree as ET
    root = ET.fromstring(text)
    doc = Doc()
    default = dict(m=[1.0, 0, 0, 1.0, 0, 0], fill=("colour", 0xFF000000), stroke=("none", 0xFF000000),
                   fill_op=1.0, stroke_op=1.0, op=1.0, sw=1.0, miter=4.0, join=0, cap=0, rule=0, skip=False)
    seen_root = [False]

    def prop(st, name, value, own):
        if name in ("fill", "stroke"):
            kind, c = colour(value)
            if kind in ("none", "colour", "current"):
                st[name] = (kind, c if kind == "colour" else 0xFF000000)
        elif name == "stroke-width":
            v, _ = number(value, 0)
            if v is not None and v >= 0:
                st["sw"] = v
        elif name == "stroke-miterlimit":
            v, _ = number(value, 0)
            if v is not None and v >= 1:
                st["miter"] = v
        elif name == "stroke-linecap":
            v = {"butt": 0, "round": 1, "square": 2}.get(trim(value))
            if v is not None:
                st["cap"] = v
        elif name == "stroke-linejoin":
            t = trim(value)
            v = {"round": 1, "bevel": 2}.get(t, 0 if t[:5] == "miter" else None)
            if v is not None:
                st["join"] = v
        elif name == "fill-rule":
            v = {"evenodd": 1, "nonzero": 0}.get(trim(value))
            if v is not None:
                st["rule"] = v
        elif name == "display":
            if trim(value) == "none":
                st["skip"] = True
        else:
            v, j = number(value, 0)
            if v is None:
                return
            if j < len(value) and value[j] == '%':
                v *= 0.01
            v = min(max(v, 0.0), 1.0)
            if name == "fill-opacity":
                st["fill_op"] = v
            elif name == "stroke-opacity":
                st["stroke_op"] = v
            else:
                own[0] = v

    def walk(el, parent):
        tag = el.tag.split('}')[-1]
        st = dict(parent)
        if tag in SKIP:
            st["skip"] = True
        if not st["skip"]:
            own = [1.0]
            geom, style = {}, None
            for name, value in el.attrib.items():
                name = name.split('}')[-1]
                if name == "style":
                    style = value
                elif name == "transform":
                    m = transform_list(value, st["m"])
                    if m is not None:
                        st["m"] = m
                elif name in PROPS:
                    prop(st, name, value, own)
                elif name in ("d", "points", "viewBox"):
                    geom[name] = value
                elif name in ("x", "y", "width", "height", "rx", "ry", "cx", "cy", "r", "x1", "y1", "x2", "y2"):
                    v, _ = number(value, 0)
                    if v is not None:
                        geom[name] = v
            if style:
                for decl in style.split(';'):
                    if ':' not in decl:
                        continue
                    name, value = decl.split(':', 1)
                    name = trim(name)
                    if name in PROPS:
                        prop(st, name, value, own)
            st["op"] = st["op"] * own[0]
            if not st["skip"]:
                if tag == "svg" and not seen_root[0]:
                    seen_root[0] = True
                    doc.width, doc.height = geom.get("width"), geom.get("height")
                    if "viewBox" in geom:
                        vals, i = [], 0
                        while len(vals) < 4:
                            v, i = number(geom["viewBox"], i)
                            if v is None:
                                break
                            vals.append(v)
                        if len(vals) == 4 and vals[2] > 0 and vals[3] > 0:
                            doc.viewbox = vals
                elif tag in SHAPES:
                    shape(tag, geom, st)
        for child in el:
            walk(child, st)

    def bake(paint, op, st):
        kind, c = paint
        a = int((c >> 24) * op * st["op"] + 0.5)
        return (kind, a << 24 | (c & 0xFFFFFF))

    def shape(tag, g, st):
        fill = st["fill"][0] != "none"
        stroke = st["stroke"][0] != "none" and st["sw"] > 0
        if not (fill or stroke):
            return
        path = []
        if tag == "rect":
            w, h = g.get("width", 0.0), g.get("height", 0.0)
            if w > 0 and h > 0:
                rx, ry = g.get("rx"), g.get("ry")
                rx, ry = (rx if rx is not None else ry or 0.0), (ry if ry is not None else rx or 0.0)
                rx, ry = min(max(rx, 0.0), w * 0.5), min(max(ry, 0.0), h * 0.5)
                x, y = g.get("x", 0.0), g.get("y", 0.0)
                path = rounded_rect(x, y, w, h, rx, ry) if rx > 0 and ry > 0 else [('rect', x, y, w, h)]
        elif tag == "circle":
            if g.get("r", 0.0) > 0:
                path = [('circle', g.get("cx", 0.0), g.get("cy", 0.0), g["r"])]
        elif tag == "ellipse":
            rx, ry = g.get("rx"), g.get("ry")
            rx, ry = (rx if rx is not None else ry or 0.0), (ry if ry is not None else rx or 0.0)
            if rx > 0 and ry > 0:
                path = [('ellipse', g.get("cx", 0.0), g.get("cy", 0.0), rx, ry)]
        elif tag == "line":
            path = [('move', g.get("x1", 0.0), g.get("y1", 0.0)), ('line', g.get("x2", 0.0), g.get("y2", 0.0))]
        elif tag in ("polyline", "polygon"):
            path = points(g.get("points", ""), tag == "polygon")
        else:
            path = path_data(g.get("d", ""))
        if not path:
            return
        f = bake(st["fill"], st["fill_op"], st)
        s = bake(st["stroke"], st["stroke_op"], st)
        doc.items.append(Item(list(st["m"]), path, f if fill else None, s if stroke else None, st["rule"],
                              st["sw"], st["miter"], st["join"], st["cap"]))

    walk(root, default)
    return doc

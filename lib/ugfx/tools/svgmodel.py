#!/usr/bin/env python3
"""A model of the SVG subset 2d/svg.asm reads, following the same rules.

    doc = parse(text)        -> Doc(viewbox, width, height, items)
    item.matrix              element -> viewBox space (a b c d e f)
    item.path                path commands: ('move', x, y) ('line', x, y)
                             ('quad', ...) ('cubic', ...) ('close',)
                             ('rect', x, y, w, h) ('circle', cx, cy, r)
                             ('ellipse', cx, cy, rx, ry)
    item.fill / item.stroke  None, ('colour', 0xAARRGGBB), ('current', alpha) or
                             ('paint', kind, spread, geom, stops, matrix, alpha):
                             a gradient (kind 1 linear x0 y0 x1 y1, 2 radial
                             cx cy r, 4 two-circle x0 y0 r0 x1 y1 r1; matrix
                             paint -> element space; alpha from the opacities)
    item.rule, .width, .miter, .join, .cap
    Group("begin", alpha) / Group("end")
                             a group drawn as one layer at alpha (opacity
                             below 1 on a container, or on a shape with
                             both fill and stroke)

Used by tests/host/svg_check.py as the reference, and by the SVG -> UIC
converter. Development-machine tooling only; not part of any OS image.
"""
import math
import re
from dataclasses import dataclass, field

SKIP = {"defs", "clipPath", "mask", "symbol", "linearGradient", "radialGradient", "pattern", "marker", "text",
        "style", "script", "title", "desc", "metadata", "foreignObject", "filter"}
MAX_USES = 8                                        # <use> instances inside instances
SHAPES = {"path", "rect", "circle", "ellipse", "line", "polyline", "polygon"}
PROPS = {"fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin", "stroke-miterlimit", "fill-rule",
         "fill-opacity", "stroke-opacity", "opacity", "display", "font-size", "color", "visibility",
         "stroke-dasharray", "stroke-dashoffset", "paint-order", "clip-path", "clip-rule", "mask"}
MAX_CLIPS = 4
INHERITS = {"fill": ["fill"], "stroke": ["stroke"], "stroke-width": ["sw"], "stroke-linecap": ["cap"],
            "stroke-linejoin": ["join"], "stroke-miterlimit": ["miter"], "fill-rule": ["rule"],
            "fill-opacity": ["fill_op"], "stroke-opacity": ["stroke_op"], "font-size": ["font"],
            "color": ["color"], "visibility": ["hidden"], "stroke-dasharray": ["dash"],
            "stroke-dashoffset": ["dash_off"], "paint-order": ["order"], "clip-rule": ["cliprule"]}
DEFERRED = ("stroke-width", "font-size", "stroke-dasharray", "stroke-dashoffset", "clip-path", "mask")
GEOM = ("x", "y", "width", "height", "rx", "ry", "cx", "cy", "r", "x1", "y1", "x2", "y2")
AXIS = dict(x="x", y="y", width="x", height="y", rx="x", ry="y", cx="x", cy="y", r="d",
            x1="x", y1="y", x2="x", y2="y")
FONT_WORDS = {"xx-small": 9.0, "x-small": 10.0, "small": 13.0, "medium": 16.0, "large": 18.0,
              "x-large": 24.0, "xx-large": 32.0}
KEYWORDS = {  # the 148 CSS named colours
    "aliceblue": 0xF0F8FF,
    "antiquewhite": 0xFAEBD7,
    "aqua": 0x00FFFF,
    "aquamarine": 0x7FFFD4,
    "azure": 0xF0FFFF,
    "beige": 0xF5F5DC,
    "bisque": 0xFFE4C4,
    "black": 0x000000,
    "blanchedalmond": 0xFFEBCD,
    "blue": 0x0000FF,
    "blueviolet": 0x8A2BE2,
    "brown": 0xA52A2A,
    "burlywood": 0xDEB887,
    "cadetblue": 0x5F9EA0,
    "chartreuse": 0x7FFF00,
    "chocolate": 0xD2691E,
    "coral": 0xFF7F50,
    "cornflowerblue": 0x6495ED,
    "cornsilk": 0xFFF8DC,
    "crimson": 0xDC143C,
    "cyan": 0x00FFFF,
    "darkblue": 0x00008B,
    "darkcyan": 0x008B8B,
    "darkgoldenrod": 0xB8860B,
    "darkgray": 0xA9A9A9,
    "darkgreen": 0x006400,
    "darkgrey": 0xA9A9A9,
    "darkkhaki": 0xBDB76B,
    "darkmagenta": 0x8B008B,
    "darkolivegreen": 0x556B2F,
    "darkorange": 0xFF8C00,
    "darkorchid": 0x9932CC,
    "darkred": 0x8B0000,
    "darksalmon": 0xE9967A,
    "darkseagreen": 0x8FBC8F,
    "darkslateblue": 0x483D8B,
    "darkslategray": 0x2F4F4F,
    "darkslategrey": 0x2F4F4F,
    "darkturquoise": 0x00CED1,
    "darkviolet": 0x9400D3,
    "deeppink": 0xFF1493,
    "deepskyblue": 0x00BFFF,
    "dimgray": 0x696969,
    "dimgrey": 0x696969,
    "dodgerblue": 0x1E90FF,
    "firebrick": 0xB22222,
    "floralwhite": 0xFFFAF0,
    "forestgreen": 0x228B22,
    "fuchsia": 0xFF00FF,
    "gainsboro": 0xDCDCDC,
    "ghostwhite": 0xF8F8FF,
    "gold": 0xFFD700,
    "goldenrod": 0xDAA520,
    "gray": 0x808080,
    "green": 0x008000,
    "greenyellow": 0xADFF2F,
    "grey": 0x808080,
    "honeydew": 0xF0FFF0,
    "hotpink": 0xFF69B4,
    "indianred": 0xCD5C5C,
    "indigo": 0x4B0082,
    "ivory": 0xFFFFF0,
    "khaki": 0xF0E68C,
    "lavender": 0xE6E6FA,
    "lavenderblush": 0xFFF0F5,
    "lawngreen": 0x7CFC00,
    "lemonchiffon": 0xFFFACD,
    "lightblue": 0xADD8E6,
    "lightcoral": 0xF08080,
    "lightcyan": 0xE0FFFF,
    "lightgoldenrodyellow": 0xFAFAD2,
    "lightgray": 0xD3D3D3,
    "lightgreen": 0x90EE90,
    "lightgrey": 0xD3D3D3,
    "lightpink": 0xFFB6C1,
    "lightsalmon": 0xFFA07A,
    "lightseagreen": 0x20B2AA,
    "lightskyblue": 0x87CEFA,
    "lightslategray": 0x778899,
    "lightslategrey": 0x778899,
    "lightsteelblue": 0xB0C4DE,
    "lightyellow": 0xFFFFE0,
    "lime": 0x00FF00,
    "limegreen": 0x32CD32,
    "linen": 0xFAF0E6,
    "magenta": 0xFF00FF,
    "maroon": 0x800000,
    "mediumaquamarine": 0x66CDAA,
    "mediumblue": 0x0000CD,
    "mediumorchid": 0xBA55D3,
    "mediumpurple": 0x9370DB,
    "mediumseagreen": 0x3CB371,
    "mediumslateblue": 0x7B68EE,
    "mediumspringgreen": 0x00FA9A,
    "mediumturquoise": 0x48D1CC,
    "mediumvioletred": 0xC71585,
    "midnightblue": 0x191970,
    "mintcream": 0xF5FFFA,
    "mistyrose": 0xFFE4E1,
    "moccasin": 0xFFE4B5,
    "navajowhite": 0xFFDEAD,
    "navy": 0x000080,
    "oldlace": 0xFDF5E6,
    "olive": 0x808000,
    "olivedrab": 0x6B8E23,
    "orange": 0xFFA500,
    "orangered": 0xFF4500,
    "orchid": 0xDA70D6,
    "palegoldenrod": 0xEEE8AA,
    "palegreen": 0x98FB98,
    "paleturquoise": 0xAFEEEE,
    "palevioletred": 0xDB7093,
    "papayawhip": 0xFFEFD5,
    "peachpuff": 0xFFDAB9,
    "peru": 0xCD853F,
    "pink": 0xFFC0CB,
    "plum": 0xDDA0DD,
    "powderblue": 0xB0E0E6,
    "purple": 0x800080,
    "rebeccapurple": 0x663399,
    "red": 0xFF0000,
    "rosybrown": 0xBC8F8F,
    "royalblue": 0x4169E1,
    "saddlebrown": 0x8B4513,
    "salmon": 0xFA8072,
    "sandybrown": 0xF4A460,
    "seagreen": 0x2E8B57,
    "seashell": 0xFFF5EE,
    "sienna": 0xA0522D,
    "silver": 0xC0C0C0,
    "skyblue": 0x87CEEB,
    "slateblue": 0x6A5ACD,
    "slategray": 0x708090,
    "slategrey": 0x708090,
    "snow": 0xFFFAFA,
    "springgreen": 0x00FF7F,
    "steelblue": 0x4682B4,
    "tan": 0xD2B48C,
    "teal": 0x008080,
    "thistle": 0xD8BFD8,
    "tomato": 0xFF6347,
    "turquoise": 0x40E0D0,
    "violet": 0xEE82EE,
    "wheat": 0xF5DEB3,
    "white": 0xFFFFFF,
    "whitesmoke": 0xF5F5F5,
    "yellow": 0xFFFF00,
    "yellowgreen": 0x9ACD32,
}
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
    order: int = 0                                  # 1: stroke before fill
    dash: object = None                             # even list of intervals, or None
    dash_off: float = 0.0
    bbox: object = None                             # its bounds, when a paint is a pattern


@dataclass
class Clip:
    items: list                                     # Items: matrix, path, rule
    units: int = 0                                  # 1 = objectBoundingBox
    next: object = None                             # the clipPath's own clip-path


@dataclass
class Mask:
    items: list                                     # what the mask draws
    units: int = 1                                  # maskUnits: 1 = objectBoundingBox
    content: int = 0                                # maskContentUnits: 1 = objectBoundingBox
    mode: int = 0                                   # 0 luminance, 1 alpha (mask-type)
    region: list = field(default_factory=lambda: [0.0, 0.0, 0.0, 0.0])


@dataclass
class Pattern:
    items: list                                     # one tile's content
    units: int = 1                                  # patternUnits: 1 = objectBoundingBox
    content: int = 0                                # patternContentUnits: 1 = objectBoundingBox
    rect: list = field(default_factory=lambda: [0.0, 0.0, 0.0, 0.0])
    matrix: list = field(default_factory=lambda: [1.0, 0.0, 0.0, 1.0, 0.0, 0.0])
    viewbox: object = None
    par: tuple = (5, 0)


@dataclass
class Group:
    kind: str                                       # "begin" / "end"
    alpha: int = 255
    clip: object = None                             # Clip
    matrix: list = None                             # the element's (begin)
    bbox: list = None                               # its content's bounds in its space
    mask: object = None                             # Mask
    begin: object = None                            # an end's begin


def invert(m):
    """umath_affine2_invert, or None when singular."""
    a, b, c, d, e, f = m
    det = a * d - b * c
    if det == 0 or det != det:
        return None
    inv = 1.0 / det
    return [d * inv, (0.0 - b) * inv, (0.0 - c) * inv, a * inv, (c * f - d * e) * inv, (b * e - a * f) * inv]


def group_bbox(begin, items):
    """svg_group_bbox: the shapes' tight bounds, corners into the group's space."""
    box = [0.0, 0.0, 0.0, 0.0]
    inv = invert(begin.matrix)
    if inv is None:
        return box
    first = True
    for it in items:
        if not isinstance(it, Item):
            continue
        b = tight_bounds(it.path)
        if b is None:
            continue
        r = mul(inv, it.matrix)
        for x, y in ((b[0], b[1]), (b[2], b[1]), (b[0], b[3]), (b[2], b[3])):
            px = r[0] * x + r[2] * y + r[4]
            py = r[1] * x + r[3] * y + r[5]
            if first:
                box, first = [px, py, px, py], False
            else:
                box = [min(box[0], px), min(box[1], py), max(box[2], px), max(box[3], py)]
    return box


@dataclass
class Doc:
    viewbox: object = None
    width: object = None
    height: object = None
    items: list = field(default_factory=list)
    par: tuple = (5, 0)                             # the root's preserveAspectRatio


ALIGNS = {"xMinYMin": 1, "xMidYMin": 2, "xMaxYMin": 3, "xMinYMid": 4, "xMidYMid": 5, "xMaxYMid": 6,
          "xMinYMax": 7, "xMidYMax": 8, "xMaxYMax": 9, "none": 0}


def par(v):
    """(align 0 none / 1..9, slice) as svg_par reads it; invalid: xMidYMid meet."""
    if v is None:
        return (5, 0)
    words = [w for w in re.split(r"[\x00- ]+", trim(v)) if w]
    if words and words[0] == "defer":
        words = words[1:]
    if not words or words[0] not in ALIGNS or len(words) > 2:
        return (5, 0)
    if len(words) == 2 and words[1] not in ("meet", "slice"):
        return (5, 0)
    return (ALIGNS[words[0]], int(len(words) == 2 and words[1] == "slice"))


def fit(vb, w, h, p):
    """svg_fit: the viewBox into w x h."""
    align, sl = p
    vx, vy, vw, vh = vb
    sx, sy = w / vw, h / vh
    fx = fy = 0.0
    if align:
        sx = sy = max(sx, sy) if sl else min(sx, sy)
        fx, fy = (0.0, 0.5, 1.0)[(align - 1) % 3], (0.0, 0.5, 1.0)[(align - 1) // 3]
    return [sx, 0.0, 0.0, sy, (w - vw * sx) * fx - vx * sx, (h - vh * sy) * fy - vy * sy]


def root_matrix(doc, x, y, size):
    """The document -> device matrix ugfx_svg_draw sets for the square (x, y, size)."""
    def square(box, p):
        m = fit(box, size, size, p)
        m[4] = m[4] + x
        m[5] = m[5] + y
        return m
    w, h = doc.width, doc.height
    if doc.viewbox and w and w > 0 and h and h > 0:
        a = fit(doc.viewbox, w, h, doc.par)
        return mul(square([0.0, 0.0, w, h], (5, 0)), a)
    if doc.viewbox:
        return square(doc.viewbox, doc.par)
    return square([0.0, 0.0, w if w and w > 0 else 300.0, h if h and h > 0 else 150.0], (5, 0))


def conditions(el):
    """requiredExtensions never passes; systemLanguage needs en or en-*."""
    for name, value in el.attrib.items():
        name = name.split('}')[-1]
        if name == "requiredExtensions":
            return False
        if name == "systemLanguage":
            ok = False
            for t in value.split(','):
                t = trim(t)
                if len(t) >= 2 and t[:2].lower() == "en" and (len(t) == 2 or t[2] == '-'):
                    ok = True
            if not ok:
                return False
    return True


def takes_part(tag):
    """Elements a switch chooses among (and conditional attributes apply to)."""
    return tag not in SKIP or tag in ("text", "foreignObject")


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


def lerp(a, b, t):
    return a + (b - a) * t


def quad_bounds(p):
    """umath_bezier_quad_bounds."""
    out = [0.0] * 4
    for k in (0, 1):
        p0, p1, p2 = p[k], p[k + 2], p[k + 4]
        lo, hi = min(p0, p2), max(p0, p2)
        den = p0 - p1 * 2 + p2
        if den != 0:
            t = (p0 - p1) / den
            if 0 < t < 1:
                v = lerp(lerp(p0, p1, t), lerp(p1, p2, t), t)
                lo, hi = min(lo, v), max(hi, v)
        out[k], out[k + 2] = lo, hi
    return out


def cubic_bounds(p):
    """umath_bezier_cubic_bounds."""
    out = [0.0] * 4
    for k in (0, 1):
        p0, p1, p2, p3 = p[k], p[k + 2], p[k + 4], p[k + 6]
        lo, hi = min(p0, p3), max(p0, p3)
        c0, c1, c2 = p1 - p0, p2 - p1, p3 - p2
        A = c0 - (c1 + c1) + c2
        B = (c1 - c0) + (c1 - c0)
        ts = []
        if A == 0:
            if B != 0:
                ts.append((0.0 - c0) / B)
        else:
            disc = B * B - ((A * c0) + (A * c0)) * 2
            if disc >= 0:
                r = math.sqrt(disc)
                ts += [((0.0 - B) + r) / (A + A), ((0.0 - B) - r) / (A + A)]
        for t in ts:
            if 0 < t < 1:
                a, b, c = lerp(p0, p1, t), lerp(p1, p2, t), lerp(p2, p3, t)
                v = lerp(lerp(a, b, t), lerp(b, c, t), t)
                lo, hi = min(lo, v), max(hi, v)
        out[k], out[k + 2] = lo, hi
    return out


def path_points(path):
    """The commands as the ugfx path builder stores them (shapes expanded)."""
    out = []
    for c in path:
        if c[0] == 'rect':
            _, x, y, w, h = c
            out += [('move', x, y), ('line', x + w, y), ('line', x + w, y + h), ('line', x, y + h), ('close',)]
        elif c[0] in ('circle', 'ellipse'):
            cx, cy, rx = c[1], c[2], c[3]
            ry = c[4] if c[0] == 'ellipse' else rx
            out.append(('move', cx + rx, cy))
            out += [('cubic', *q) for q in axis_arc(cx, cy, rx, ry, 0.0, 2 * math.pi)]
            out.append(('close',))
        else:
            out.append(c)
    return out


def tight_bounds(path):
    """ugfx_path_bounds_tight -> [x0, y0, x1, y1] or None."""
    box, cur = None, None

    def grow(b):
        nonlocal box
        box = list(b) if box is None else [min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3])]
    for c in path_points(path):
        if c[0] in ('move', 'line'):
            grow([c[1], c[2], c[1], c[2]])
            cur = c[1:3]
        elif c[0] == 'quad':
            grow(quad_bounds([*cur, *c[1:]]))
            cur = c[3:5]
        elif c[0] == 'cubic':
            grow(cubic_bounds([*cur, *c[1:]]))
            cur = c[5:7]
    return box


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


def length_at(v, i, axis, st):
    """(user units, is a percentage, next index) or (None, False, i), as svg_length reads it."""
    val, i = number(v, i)
    if val is None or i >= len(v):
        return val, False, i
    c = v[i]
    if c == '%':
        val = val * 0.01
        if axis == "x":
            return val * st["vw"], True, i + 1
        if axis == "y":
            return val * st["vh"], True, i + 1
        if axis == "font":
            return val * st["font"], True, i + 1
        return val * math.sqrt((st["vw"] * st["vw"] + st["vh"] * st["vh"]) * 0.5), True, i + 1
    if not 'a' <= chr(ord(c) | 0x20) <= 'z':
        return val, False, i
    if i + 2 > len(v):
        return None, False, i
    u = "".join(chr(ord(ch) | 0x20) for ch in v[i:i + 2])
    if u == "px":
        return val, False, i + 2
    if u == "em":
        return val * st["font"], False, i + 2
    if u == "ex":
        return val * st["font"] * 0.5, False, i + 2
    f = {"pt": 96.0 / 72.0, "pc": 16.0, "mm": 96.0 / 25.4, "cm": 96.0 / 2.54, "in": 96.0}.get(u)
    return (val * f if f is not None else None), False, i + 2


def length(v, axis, st):
    val, pct, _ = length_at(v, 0, axis, st)
    return val, pct


def dash_list(v, st):
    """The intervals (an odd list repeated), or None for solid, as svg_dash_list makes them."""
    vals, total, i = [], 0.0, 0
    while True:
        val, _, j = length_at(v, i, "d", st)
        if val is None:
            break
        if val < 0:
            return None
        vals.append(val)
        total = total + val
        i = j
    if any(c not in " ,\t\r\n" for c in v[i:]) or not vals or not total > 0:
        return None
    return vals * 2 if len(vals) % 2 else vals


def paint_order(v):
    """1 when stroke comes before fill, 0 otherwise, None when invalid."""
    t = trim(v)
    if t == "normal":
        return 0
    first = None
    for word in re.split(r"[\x00- ]+", t):
        if not word or word == "markers":
            continue
        if word not in ("fill", "stroke"):
            return None
        if first is None:
            first = 1 if word == "stroke" else 0
    return first or 0


def font_size(v, st):
    t = trim(v)
    if t in FONT_WORDS:
        return FONT_WORDS[t]
    if t == "larger":
        return st["font"] * 1.2
    if t == "smaller":
        return st["font"] / 1.2
    f, _ = length(t, "font", st)
    return f if f is not None and f >= 0 else None


def alpha_slash(s, i):
    i = SEP.match(s, i).end()
    if i < len(s) and s[i] == '/':
        i = SEP.match(s, i + 1).end()
    return i


def byte(v):
    return int(min(max(v, 0.0), 255.0) + 0.5)


def hsl(s, i):
    vals = []
    while len(vals) < 4:
        i = alpha_slash(s, i)
        v, j = number(s, i)
        if v is None:
            break
        i = j
        if not vals:
            if s[i:i + 3].lower() == "deg":
                i += 3
        elif len(vals) < 3:
            if i < len(s) and s[i] == '%':
                i += 1
            v = v * 0.01
        elif i < len(s) and s[i] == '%':
            i += 1
            v = v * 0.01
        vals.append(v)
    i = SEP.match(s, i).end()
    if i >= len(s) or s[i] != ')' or len(vals) < 3:
        return None, 0
    alpha = byte((vals[3] if len(vals) == 4 else 1.0) * 255.0)
    h = vals[0] - math.floor(vals[0] / 360.0) * 360.0
    sat = min(max(vals[1], 0.0), 1.0)
    light = min(max(vals[2], 0.0), 1.0)
    a = sat * min(light, 1.0 - light)
    rgb = 0
    for n in (0.0, 8.0, 4.0):
        k = h / 30.0 + n
        k = k - math.floor(k / 12.0) * 12.0
        t = max(min(min(k - 3.0, 9.0 - k), 1.0), -1.0)
        rgb = rgb << 8 | byte((light - t * a) * 255.0)
    return "colour", alpha << 24 | rgb


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
    if low.startswith("hsla(") or low.startswith("hsl("):
        return hsl(s, s.index("(") + 1)
    if low.startswith("rgba(") or low.startswith("rgb("):
        i = s.index("(") + 1
        vals = []
        while len(vals) < 4:
            i = alpha_slash(s, i)
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


def url_ref(v):
    """svg_url: url( [quote] [#] id ... ) -> (id, the text after ')') or None."""
    i = 4
    while i < len(v) and ord(v[i]) <= 32:
        i += 1
    if i >= len(v):
        return None
    q = v[i] if v[i] in "\"'" else None
    if q:
        i += 1
    if i < len(v) and v[i] == '#':
        i += 1
    j = i
    while j < len(v) and v[j] != ')' and ord(v[j]) > 32 and v[j] != q:
        j += 1
    if j >= len(v):
        return None
    k = v.find(')', j)
    if k < 0 or j == i:
        return None
    return v[i:j], v[k + 1:]


GRAD_VALUES = ("x1", "y1", "x2", "y2", "cx", "cy", "r", "fx", "fy", "fr")
GRAD_DEFAULTS = (0.0, 0.0, 1.0, 0.0, 0.5, 0.5, 0.5, 0.5, 0.5, 0.0)
GRAD_AXIS = (0, 1, 0, 1, 0, 1, 2, 0, 1, 2)


def scan_gradients(root):
    """Every gradient: dict(id, href, kind, have, val, pct, units, spread, m, stops)."""
    grads = []
    for el in root.iter():
        tag = el.tag.split('}')[-1]
        if tag not in ("linearGradient", "radialGradient"):
            continue
        g = dict(id=None, href=None, kind=1 if tag == "linearGradient" else 2, have=set(), val={}, pct=set(),
                 units=0, spread=0, m=[1.0, 0, 0, 1.0, 0, 0], stops=[])
        for name, value in el.attrib.items():
            name = name.split('}')[-1] if not name.startswith("{http://www.w3.org/1999/xlink}") else "xlink:href"
            if name == "id":
                g["id"] = trim(value)
            elif name in ("href", "xlink:href"):
                v = trim(value)
                if v.startswith("#"):
                    g["href"] = v[1:]
            elif name in GRAD_VALUES:
                n, j = number(value, 0)
                if n is not None:
                    pct = j < len(value) and value[j] == '%'
                    g["val"][name] = n * 0.01 if pct else n
                    g["have"].add(name)
                    (g["pct"].add if pct else g["pct"].discard)(name)
            elif name == "gradientUnits":
                v = {"objectBoundingBox": 0, "userSpaceOnUse": 1}.get(trim(value))
                if v is not None:
                    g["units"] = v
                    g["have"].add("units")
            elif name == "spreadMethod":
                v = {"pad": 0, "repeat": 1, "reflect": 2}.get(trim(value))
                if v is not None:
                    g["spread"] = v
                    g["have"].add("spread")
            elif name == "gradientTransform":
                m = transform_list(value, [1.0, 0, 0, 1.0, 0, 0])
                if m is not None:
                    g["m"] = m
                    g["have"].add("transform")
        for stop in el.iter():
            if stop.tag.split('}')[-1] != "stop":
                continue
            st = dict(offset=0.0, colour=0xFF000000, opacity=1.0)

            def stop_prop(name, value):
                if name == "stop-color":
                    kind, c = colour(value)
                    if kind == "colour":
                        st["colour"] = c
                    elif kind in ("current", "inherit"):
                        st["colour"] = 0xFF000000
                    elif kind == "none":
                        st["colour"] = 0
                elif name in ("offset", "stop-opacity"):
                    n, j = number(value, 0)
                    if n is None:
                        return
                    if j < len(value) and value[j] == '%':
                        n *= 0.01
                    n = min(max(n, 0.0), 1.0)
                    st["offset" if name == "offset" else "opacity"] = n
            style = None
            for name, value in stop.attrib.items():
                if name == "style":
                    style = value
                else:
                    stop_prop(name, value)
            if style:
                for decl in style.split(';'):
                    if ':' in decl:
                        name, value = decl.split(':', 1)
                        stop_prop(trim(name), value)
            a = int((st["colour"] >> 24) * st["opacity"] + 0.5)
            g["stops"].append((st["offset"], a << 24 | (st["colour"] & 0xFFFFFF)))
        grads.append(g)
    return grads


def resolve_gradient(grads, rid, path, viewport):
    """ugfx_svg_defs_paint: None (no such id), 'none', ('colour', c) or a paint tuple."""
    def find(i):
        for g in grads:
            if g["id"] == i:
                return g
        return None
    g = find(rid)
    if g is None:
        return None
    kind = g["kind"]
    have, val, pct = set(), {}, set()
    units, spread, m, stops = 0, 0, [1.0, 0, 0, 1.0, 0, 0], []
    hops = 0
    while True:
        if g["kind"] == kind:
            for v in GRAD_VALUES:
                if v not in have and v in g["have"]:
                    val[v] = g["val"][v]
                    have.add(v)
                    if v in g["pct"]:
                        pct.add(v)
        for key in ("units", "spread", "transform"):
            if key not in have and key in g["have"]:
                have.add(key)
                if key == "units":
                    units = g["units"]
                elif key == "spread":
                    spread = g["spread"]
                else:
                    m = list(g["m"])
        if not stops and g["stops"]:
            stops = list(g["stops"])
        if hops >= 16 or not g["href"]:
            break
        hops += 1
        nxt = find(g["href"])
        if nxt is None:
            break
        g = nxt
    if not stops:
        return "none"
    if len(stops) == 1:
        return ("colour", stops[-1][1])
    for i, v in enumerate(GRAD_VALUES):
        if v not in have:
            val[v] = GRAD_DEFAULTS[i]
            pct.add(v)
            if v == "fx":
                val["fx"] = val["cx"]
                (pct.add if "cx" in pct else pct.discard)("fx")
            if v == "fy":
                val["fy"] = val["cy"]
                (pct.add if "cy" in pct else pct.discard)("fy")
    if units == 0:
        box = tight_bounds(path)
        if box is None:
            return "none"
        w, h = box[2] - box[0], box[3] - box[1]
        if not (w > 0 and h > 0):
            return "none"
        matrix = mul([w, 0.0, 0.0, h, box[0], box[1]], m)
    else:
        vw, vh = viewport
        diag = math.sqrt((vw * vw + vh * vh) * 0.5)
        for i, v in enumerate(GRAD_VALUES):
            if v in pct:
                val[v] = val[v] * (vw, vh, diag)[GRAD_AXIS[i]]
        matrix = list(m)
    last = ("colour", stops[-1][1])
    if kind == 1:
        x1, y1, x2, y2 = val["x1"], val["y1"], val["x2"], val["y2"]
        if (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1) == 0:
            return last
        return ('paint', 1, spread, [x1, y1, x2, y2], stops, matrix)
    r = val["r"]
    if not r > 0:
        return last
    if val["fx"] == val["cx"] and val["fy"] == val["cy"] and val["fr"] == 0:
        return ('paint', 2, spread, [val["cx"], val["cy"], r], stops, matrix)
    fr = max(val["fr"], 0.0)
    if val["fx"] == val["cx"] and val["fy"] == val["cy"] and fr == r:
        return last                     # the same circle twice
    return ('paint', 4, spread, [val["fx"], val["fy"], fr, val["cx"], val["cy"], r], stops, matrix)


IDENT = re.compile(r"[A-Za-z0-9_-]+")


def css_skip(t, i):
    """Whitespace, /* comments */, <!-- --> and CDATA markers."""
    while i < len(t):
        if ord(t[i]) <= 32:
            i += 1
        elif t.startswith("/*", i):
            j = t.find("*/", i + 2)
            i = len(t) if j < 0 else j + 2
        elif t.startswith("<![CDATA[", i):
            i += 9
        elif t.startswith("<!--", i):
            i += 4
        elif t.startswith("-->", i) or t.startswith("]]>", i):
            i += 3
        else:
            break
    return i


def css_rules(text):
    """The supported rules of a style sheet: (kind, spec, name, elem, declarations)."""
    rules, i = [], 0
    while True:
        i = css_skip(text, i)
        if i >= len(text):
            break
        if text[i] == '@':
            depth = 0
            while i < len(text):
                c = text[i]
                i += 1
                if c == '{':
                    depth += 1
                elif c == '}':
                    depth -= 1
                    if depth <= 0:
                        break
                elif c == ';' and depth == 0:
                    break
            continue
        b = text.find('{', i)
        if b < 0:
            break
        sels = text[i:b]
        e = text.find('}', b + 1)
        decls = text[b + 1:] if e < 0 else text[b + 1:e]
        i = len(text) if e < 0 else e + 1
        for sel in sels.split(','):
            sel = trim(sel)
            if not sel:
                continue
            if sel == '*':
                rules.append((5, 0, None, None, decls))
            elif sel[0] in '.#':
                if IDENT.fullmatch(sel[1:]):
                    rules.append((2, 10, sel[1:], None, decls) if sel[0] == '.' else (3, 100, sel[1:], None, decls))
            elif '.' in sel:
                elem, cls = sel.split('.', 1)
                if elem and IDENT.fullmatch(elem) and IDENT.fullmatch(cls):
                    rules.append((4, 11, cls, elem, decls))
            elif IDENT.fullmatch(sel):
                rules.append((1, 1, sel, None, decls))
    return sorted(rules, key=lambda r: r[1])          # stable: document order within a specificity


def css_matches(rule, tag, el_id, classes):
    kind, _, name, elem, _ = rule
    if kind == 5:
        return True
    if kind == 1:
        return tag == name
    if kind == 3:
        return el_id == name
    if kind == 4 and tag != elem:
        return False
    return name in classes


def trim(v):
    v = v.strip(" \t\r\n")
    if len(v) >= 10 and v[-10] == '!':
        v = v[:-10].strip(" \t\r\n")
    return v


def parse(text):
    import xml.etree.ElementTree as ET
    root = ET.fromstring(text)
    doc = Doc()
    grads = scan_gradients(root)
    rules = []
    for el in root.iter():
        if el.tag.split('}')[-1] == "style" and el.text:
            rules += css_rules(el.text)
    rules.sort(key=lambda r: r[1])
    ids = {}
    for el in root.iter():
        if "id" in el.attrib:
            ids.setdefault(trim(el.attrib["id"]), el)
    default = dict(m=[1.0, 0, 0, 1.0, 0, 0], fill=("colour", 0xFF000000), stroke=("none", 0xFF000000),
                   fill_op=1.0, stroke_op=1.0, op=1.0, sw=1.0, miter=4.0, join=0, cap=0, rule=0, skip=False,
                   font=16.0, vw=300.0, vh=150.0, color=None, hidden=False, order=0, dash=None, dash_off=0.0,
                   cliprule=0)
    seen_root = [False]
    clipmode = [0]                                  # 1: a clip's content (geometry only)
    compiling = [0]                                 # clipPaths / masks being compiled

    def ref(raw, prop, kind, st, uses):
        """The element's compiled clip-path / mask, or None."""
        v = raw.get(prop)
        if clipmode[0] or v is None:
            return None
        t = trim(v)
        if t == "none" or t[:4].lower() != "url(":
            return None
        r = url_ref(t)
        return compile_ref(r[0], kind, st, uses) if r else None

    def pattern_attrs(rec, el, st, uses):
        """svg_pattern_attrs: the tile, units, transform, viewBox; href gives what is missing."""
        given, raw_rect, href = set(), ["0", "0", "0", "0"], None
        for name, value in el.attrib.items():
            name = name.split('}')[-1]
            given.add(name)
            if name in ("x", "y", "width", "height"):
                raw_rect[("x", "y", "width", "height").index(name)] = value
            elif name == "patternUnits":
                rec.units = int(trim(value) == "objectBoundingBox")
            elif name == "patternContentUnits":
                rec.content = int(trim(value) == "objectBoundingBox")
            elif name == "patternTransform":
                m = transform_list(value, rec.matrix)
                if m is not None:
                    rec.matrix = m
            elif name == "viewBox":
                vals, i = [], 0
                while len(vals) < 4:
                    v, i = number(value, i)
                    if v is None:
                        break
                    vals.append(v)
                rec.viewbox = vals if len(vals) == 4 and vals[2] > 0 and vals[3] > 0 else None
            elif name == "preserveAspectRatio":
                rec.par = par(value)
            elif name == "href":
                t = trim(value)
                if t.startswith('#'):
                    href = t[1:]
        for i, v in enumerate(raw_rect):
            if rec.units:
                val, j = number(v, 0)
                if val is not None and j < len(v) and v[j] == '%':
                    val = val * 0.01
            else:
                val, _ = length(v, "x" if i % 2 == 0 else "y", st)
            rec.rect[i] = val if val is not None else 0.0
        base = compile_ref(href, "pattern", st, uses) if href is not None else None
        if base is not None:
            if "patternUnits" not in given:
                rec.units = base.units
            if "patternContentUnits" not in given:
                rec.content = base.content
            for i, name in enumerate(("x", "y", "width", "height")):
                if name not in given:
                    rec.rect[i] = base.rect[i]
            if "patternTransform" not in given:
                rec.matrix = list(base.matrix)
            if "viewBox" not in given:
                rec.viewbox = base.viewbox
            if "preserveAspectRatio" not in given:
                rec.par = base.par
            if not rec.items:
                rec.items = base.items

    def clip_ref(raw, st, uses):
        return ref(raw, "clip-path", "clip", st, uses)

    def mask_ref(raw, st, uses):
        return ref(raw, "mask", "mask", st, uses)

    def compile_ref(cid, kind, st, uses):
        el = ids.get(cid)
        want = {"clip": "clipPath", "mask": "mask", "pattern": "pattern"}[kind]
        if compiling[0] >= MAX_CLIPS or el is None or el.tag.split('}')[-1] != want:
            return None
        compiling[0] += 1
        base = dict(default, vw=st["vw"], vh=st["vh"], font=st["font"])
        saved, doc.items = doc.items, []
        saved_mode, clipmode[0] = clipmode[0], int(kind == "clip")
        walk(el, base, uses, kind)
        clipmode[0] = saved_mode
        rec = {"clip": Clip, "mask": Mask, "pattern": Pattern}[kind](doc.items)
        doc.items = saved
        if kind == "pattern":
            pattern_attrs(rec, el, st, uses)
        elif kind == "clip":
            for name, value in el.attrib.items():
                name = name.split('}')[-1]
                if name == "clipPathUnits" and trim(value) == "objectBoundingBox":
                    rec.units = 1
                elif name == "clip-path":
                    t = trim(value)
                    r = url_ref(t) if t[:4].lower() == "url(" else None
                    if r:
                        rec.next = compile_ref(r[0], "clip", st, uses)
        else:
            raw_region = ["-10%", "-10%", "120%", "120%"]
            for name, value in el.attrib.items():
                name = name.split('}')[-1]
                if name in ("x", "y", "width", "height"):
                    raw_region[("x", "y", "width", "height").index(name)] = value
                elif name == "maskUnits":
                    rec.units = int(trim(value) == "objectBoundingBox")
                elif name == "maskContentUnits":
                    rec.content = int(trim(value) == "objectBoundingBox")
                elif name == "mask-type":
                    rec.mode = int(trim(value) == "alpha")
            for i, v in enumerate(raw_region):
                if rec.units:
                    val, j = number(v, 0)
                    if val is None:
                        continue
                    if j < len(v) and v[j] == '%':
                        val = val * 0.01
                else:
                    val, _ = length(v, "x" if i % 2 == 0 else "y", st)
                    if val is None:
                        continue
                rec.region[i] = val
        compiling[0] -= 1
        return rec

    def prop(st, name, value, own, parent):
        if trim(value) == "inherit":
            for k in INHERITS.get(name, ()):
                st[k] = parent[k]
            own[1].pop(name, None)
            if name == "opacity":
                own[0] = 1.0
            return
        if name in DEFERRED:
            own[1][name] = value                    # resolved once font-size is known
        elif name == "color":
            kind, c = colour(value)
            if kind == "colour":
                st["color"] = c
        elif name == "visibility":
            t = trim(value)
            if t in ("visible", "hidden", "collapse"):
                st["hidden"] = t != "visible"
        elif name == "paint-order":
            o = paint_order(value)
            if o is not None:
                st["order"] = o
        elif name == "clip-rule":
            t = trim(value)
            if t in ("evenodd", "nonzero"):
                st["cliprule"] = int(t == "evenodd")
        elif name in ("fill", "stroke"):
            v = value.strip(" \t\r\n")
            if len(v) >= 10 and v[-10] == '!':
                v = v[:-10].strip(" \t\r\n")
            if v.startswith("url("):
                ref = url_ref(v)
                if ref:
                    rid, rest = ref
                    kind, c = colour(rest)
                    if kind not in ("none", "colour", "current"):
                        kind = "none"
                    st[name] = ("url", rid, kind, c if kind == "colour" else 0xFF000000)
                return
            kind, c = colour(value)
            if kind in ("none", "colour", "current"):
                st[name] = (kind, c if kind == "colour" else 0xFF000000)
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

    def walk(el, parent, uses=0, inst=None):
        """inst: (width, height) or None from the <use> whose root el is."""
        tag = el.tag.split('}')[-1]
        st = dict(parent)
        symroot = tag == "symbol" and isinstance(inst, tuple)
        cliproot = (tag == "clipPath" and inst == "clip") or (tag == "mask" and inst == "mask") or \
            (tag == "pattern" and inst == "pattern")
        if (takes_part(tag) or symroot or cliproot) and not conditions(el):
            return
        if tag in SKIP and not (symroot or cliproot):
            st["skip"] = True
        if not st["skip"]:
            own = [1.0, {}]
            geom, style, el_id, classes, href = {}, None, None, [], None
            for name, value in el.attrib.items():
                name = name.split('}')[-1]
                if name == "style":
                    style = value
                elif name == "id":
                    el_id = trim(value)
                elif name == "class":
                    classes = value.split()
                elif name == "href":
                    v = trim(value)
                    if v.startswith('#'):
                        href = v[1:]
                elif name == "transform":
                    m = transform_list(value, st["m"])
                    if m is not None:
                        st["m"] = m
                elif name in PROPS:
                    prop(st, name, value, own, parent)
                elif name in ("d", "points", "viewBox", "preserveAspectRatio"):
                    geom[name] = value
                elif name in GEOM:
                    own[1]["geom:" + name] = value
            for decls in [r[4] for r in rules if css_matches(r, tag, el_id, classes)] + ([style] if style else []):
                for decl in decls.split(';'):
                    if ':' not in decl:
                        continue
                    name, value = decl.split(':', 1)
                    name = trim(name)
                    if name in PROPS:
                        prop(st, name, value, own, parent)
            raw = own[1]
            if "font-size" in raw:
                f = font_size(raw["font-size"], st)
                if f is not None:
                    st["font"] = f
            if "stroke-width" in raw:
                v, _ = length(raw["stroke-width"], "d", st)
                if v is not None and v >= 0:
                    st["sw"] = v
            if "stroke-dasharray" in raw:
                t = trim(raw["stroke-dasharray"])
                st["dash"] = None if t == "none" else dash_list(t, st)
            if "stroke-dashoffset" in raw:
                v, _ = length(raw["stroke-dashoffset"], "d", st)
                if v is not None:
                    st["dash_off"] = v
            for name in GEOM:
                if "geom:" + name in raw:
                    v, pct = length(raw["geom:" + name], AXIS[name], st)
                    if v is None or (pct and tag == "svg" and not seen_root[0] and name in ("width", "height")):
                        continue
                    geom[name] = v
            opened = vp = None
            if not st["skip"]:
                if tag not in SHAPES and not clipmode[0] and not cliproot:
                    rec = clip_ref(raw, st, uses)
                    mrec = mask_ref(raw, st, uses)
                    if rec or mrec or own[0] < 1.0:
                        opened = Group("begin", int(own[0] * 255.0 + 0.5), rec, list(st["m"]), mask=mrec)
                        doc.items.append(opened)
                        opened_at = len(doc.items)
                if symroot:
                    vp = symbol_map(st, geom, inst)
                if tag == "use":
                    target = ids.get(href) if href is not None else None
                    if target is not None and uses < MAX_USES:
                        u = dict(st)
                        u["m"] = mul(st["m"], [1.0, 0.0, 0.0, 1.0, geom.get("x", 0.0), geom.get("y", 0.0)])
                        wh = (geom.get("width", st["vw"]), geom.get("height", st["vh"]))
                        walk(target, u, uses + 1, wh)
                elif tag == "svg" and seen_root[0]:
                    st["m"] = mul(st["m"], [1.0, 0.0, 0.0, 1.0, geom.get("x", 0.0), geom.get("y", 0.0)])
                    w, h = geom.get("width", st["vw"]), geom.get("height", st["vh"])
                    if w > 0 and h > 0:
                        vp = view_clip(st, 0.0, 0.0, w, h)
                        view_map(st, geom, w, h)
                    else:
                        st["skip"] = True
                elif tag == "svg":
                    seen_root[0] = True
                    doc.par = par(geom.get("preserveAspectRatio"))
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
                            if doc.par[1] and doc.par[0]:
                                vw, vh = 1.0, 1.0
                                if doc.width and doc.width > 0 and doc.height and doc.height > 0:
                                    vw, vh = doc.width, doc.height
                                f = fit(vals, vw, vh, doc.par)
                                vp = view_clip(st, (0.0 - f[4]) / f[0], (0.0 - f[5]) / f[0], vw / f[0], vh / f[0])
                    st["vw"], st["vh"] = viewport()
                elif tag in SHAPES:
                    shape(tag, geom, st, own[0], raw, uses)
        else:
            opened = vp = None
        chosen = False
        for child in el:
            if tag == "switch":
                ctag = child.tag.split('}')[-1]
                if takes_part(ctag):
                    if chosen or not conditions(child):
                        continue
                    chosen = True
            walk(child, st, uses)
        if vp:
            vp[0].bbox = group_bbox(vp[0], doc.items[vp[1]:])
            doc.items.append(Group("end", 255, vp[0].clip, begin=vp[0]))
        if opened:
            if opened.clip or opened.mask:
                opened.bbox = group_bbox(opened, doc.items[opened_at:])
            doc.items.append(Group("end", opened.alpha, opened.clip, mask=opened.mask, begin=opened))

    def symbol_map(st, geom, wh):
        vp = view_clip(st, 0.0, 0.0, wh[0], wh[1])
        view_map(st, geom, wh[0], wh[1])
        return vp

    def view_clip(st, x, y, w, h):
        """svg_view_clip: a group clipping to that rectangle -> (its begin, where its content starts)."""
        if clipmode[0]:
            return None
        rect = Item([1.0, 0.0, 0.0, 1.0, 0.0, 0.0], [('rect', x, y, w, h)], None, None, 0, 1.0, 4.0, 0, 0)
        begin = Group("begin", 255, Clip([rect]), list(st["m"]))
        doc.items.append(begin)
        return begin, len(doc.items)

    def view_map(st, geom, w, h):
        """svg_view_map: a valid viewBox fitted into w x h becomes the viewport inside."""
        st["vw"], st["vh"] = w, h
        if "viewBox" not in geom:
            return
        vals, i = [], 0
        while len(vals) < 4:
            v, i = number(geom["viewBox"], i)
            if v is None:
                return
            vals.append(v)
        if not (vals[2] > 0 and vals[3] > 0):
            return
        st["vw"], st["vh"] = vals[2], vals[3]
        st["m"] = mul(st["m"], fit(vals, w, h, par(geom.get("preserveAspectRatio"))))

    def bake(paint, op, st):
        kind, c = paint
        a = int((c >> 24) * op * st["op"] + 0.5)
        return (kind, a << 24 | (c & 0xFFFFFF))

    def viewport():
        if doc.viewbox:
            return doc.viewbox[2], doc.viewbox[3]
        return (doc.width if doc.width and doc.width > 0 else 300.0,
                doc.height if doc.height and doc.height > 0 else 150.0)

    def current(p, st):
        if p[0] == "current" and st["color"] is not None:
            return "colour", st["color"]
        return p

    def paint_of(p, op, st, path, uses):
        """The item's paint, or None when it draws nothing."""
        if p[0] != "url":
            return bake(current(p, st), op, st) if p[0] != "none" else None
        _, rid, fb_kind, fb_colour = p
        r = resolve_gradient(grads, rid, path, viewport())
        if r is None:
            pat = compile_ref(rid, "pattern", st, uses)
            if pat is not None:
                return ("pattern", pat, int(255 * op * st["op"] + 0.5))
            return bake(current((fb_kind, fb_colour), st), op, st) if fb_kind != "none" else None
        if r == "none":
            return None
        if r[0] == "colour":
            return bake(("colour", r[1]), op, st)
        return r + (int(255 * op * st["op"] + 0.5),)

    def shape(tag, g, st, own, raw, uses):
        if st["hidden"]:
            return
        if clipmode[0]:
            path = geometry(tag, g)
            if path:
                doc.items.append(Item(list(st["m"]), path, None, None, st["cliprule"], 1.0, 4.0, 0, 0))
            return
        fill = st["fill"][0] != "none"
        stroke = st["stroke"][0] != "none" and st["sw"] > 0
        if not (fill or stroke):
            return
        rec = clip_ref(raw, st, uses)
        mrec = mask_ref(raw, st, uses)
        group = own < 1.0 and fill and stroke
        if own < 1.0 and not group:
            st["op"] = own * st["op"]
        path = geometry(tag, g)
        if not path:
            return
        f = paint_of(st["fill"], st["fill_op"], st, path, uses) if fill else None
        s = paint_of(st["stroke"], st["stroke_op"], st, path, uses) if stroke else None
        item = Item(list(st["m"]), path, f, s, st["rule"], st["sw"], st["miter"], st["join"], st["cap"],
                    st["order"], st["dash"], st["dash_off"])
        if (f and f[0] == "pattern") or (s and s[0] == "pattern"):
            item.bbox = tight_bounds(path)
        if group or rec or mrec:
            begin = Group("begin", int(own * 255.0 + 0.5) if group else 255, rec, list(st["m"]), mask=mrec)
            if rec or mrec:
                begin.bbox = group_bbox(begin, [item])
            doc.items += [begin, item, Group("end", begin.alpha, rec, mask=mrec, begin=begin)]
        else:
            doc.items.append(item)

    def geometry(tag, g):
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
        return path

    walk(root, default)
    return doc

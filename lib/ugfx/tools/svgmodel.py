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
         "stroke-dasharray", "stroke-dashoffset", "paint-order", "clip-path", "clip-rule", "mask",
         "marker-start", "marker-mid", "marker-end", "marker", "font-family", "font-weight", "font-style",
         "text-anchor", "letter-spacing", "word-spacing", "filter", "baseline-shift", "dominant-baseline",
         "alignment-baseline", "text-decoration"}
MARKED = {"path", "line", "polyline", "polygon"}
MAX_CLIPS = 4
INHERITS = {"fill": ["fill"], "stroke": ["stroke"], "stroke-width": ["sw"], "stroke-linecap": ["cap"],
            "stroke-linejoin": ["join"], "stroke-miterlimit": ["miter"], "fill-rule": ["rule"],
            "fill-opacity": ["fill_op"], "stroke-opacity": ["stroke_op"], "font-size": ["font"],
            "color": ["color"], "visibility": ["hidden"], "stroke-dasharray": ["dash"],
            "stroke-dashoffset": ["dash_off"], "paint-order": ["order"], "clip-rule": ["cliprule"],
            "marker-start": ["m0"], "marker-mid": ["m1"], "marker-end": ["m2"], "marker": ["m0", "m1", "m2"],
            "font-family": ["family"], "font-weight": ["weight"], "font-style": ["fstyle"],
            "text-anchor": ["anchor"], "letter-spacing": ["lspace"], "word-spacing": ["wspace"],
            "dominant-baseline": ["dbase"], "alignment-baseline": ["dbase"]}
DEFERRED = ("stroke-width", "font-size", "stroke-dasharray", "stroke-dashoffset", "clip-path", "mask",
            "letter-spacing", "word-spacing", "filter", "baseline-shift")
BASELINES = {"auto": 0, "alphabetic": 0, "use-script": 0, "no-change": 0, "reset-size": 0, "middle": 1,
             "central": 2, "hanging": 3, "mathematical": 4, "text-before-edge": 5, "text-top": 5,
             "before-edge": 5, "text-after-edge": 6, "text-bottom": 6, "after-edge": 6, "ideographic": 6}
TP_STEPS = 32                                       # line segments per curve along a textPath
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
class Marker:
    items: list                                     # its content
    units: int = 0                                  # 1 = userSpaceOnUse, 0 = strokeWidth
    orient: int = 0                                 # 0 angle, 1 auto, 2 auto-start-reverse
    clip: int = 1
    angle: float = 0.0
    ref: list = field(default_factory=lambda: [0.0, 0.0])
    size: list = field(default_factory=lambda: [3.0, 3.0])
    vbm: object = None                              # viewBox -> viewport, or None


@dataclass
class MarkerItem:
    matrix: list                                    # marker space -> doc
    marker: object


def vertices(path):
    """svg_vertices: [x, y, in, out, flags] per vertex."""
    vs, cur, start, first, opened = [], [0.0, 0.0], [0.0, 0.0], 0, False

    def nonzero(d):
        return d[0] != 0.0 or d[1] != 0.0

    def seg(ds, de, p):
        nonlocal cur, start, first, opened
        if not opened:
            start = list(cur)
            vs.append([cur[0], cur[1], 0.0, 0.0, 0])
            first, opened = len(vs) - 1, True
        last = vs[-1]
        if not last[4] & 2:
            last[3] = math.atan2(ds[1], ds[0])
            last[4] |= 2
        cur = [p[0], p[1]]
        vs.append([p[0], p[1], math.atan2(de[1], de[0]), 0.0, 1])

    for c in path:
        op = c[0]
        if op == 'move':
            cur = [c[1], c[2]]
            start = list(cur)
            vs.append([c[1], c[2], 0.0, 0.0, 0])
            first, opened = len(vs) - 1, True
        elif op == 'line':
            d = [c[1] - cur[0], c[2] - cur[1]]
            seg(d, d, c[1:3])
        elif op == 'quad':
            ds = [c[1] - cur[0], c[2] - cur[1]]
            if not nonzero(ds):
                ds = [c[3] - cur[0], c[4] - cur[1]]
            de = [c[3] - c[1], c[4] - c[2]]
            if not nonzero(de):
                de = [c[3] - cur[0], c[4] - cur[1]]
            seg(ds, de, c[3:5])
        elif op == 'cubic':
            ds = [c[1] - cur[0], c[2] - cur[1]]
            if not nonzero(ds):
                ds = [c[3] - cur[0], c[4] - cur[1]]
            if not nonzero(ds):
                ds = [c[5] - cur[0], c[6] - cur[1]]
            de = [c[5] - c[3], c[6] - c[4]]
            if not nonzero(de):
                de = [c[5] - c[1], c[6] - c[2]]
            if not nonzero(de):
                de = [c[5] - cur[0], c[6] - cur[1]]
            seg(ds, de, c[5:7])
        elif op == 'close':
            if not opened:
                continue
            d = [start[0] - cur[0], start[1] - cur[1]]
            if nonzero(d):
                seg(d, d, list(start))
            last, f = vs[-1], vs[first]
            if f[4] & 2:
                last[3] = f[3]
                last[4] |= 2
            if last is not f and last[4] & 1:
                f[2] = last[2]
                f[4] |= 1
            opened = False
            cur = list(start)
    return vs


def marker_angle(v):
    if v[4] == 3:
        d = v[3] - v[2]
        if d > math.pi:
            d = d - 2 * math.pi
        elif -math.pi > d:
            d = d + 2 * math.pi
        return v[2] + d * 0.5
    if v[4] == 1:
        return v[2]
    if v[4] == 2:
        return v[3]
    return 0.0


@dataclass
class ImageItem:
    matrix: list
    path: list                                      # the viewport (x, y, w, h)
    image: object                                   # what image_fn returned
    dest: list                                      # x, y, w, h it is drawn at
    clip: int                                       # 1: slice, clipped to the viewport
    alpha: int


def data_uri(href):
    """svg_data_uri: the bytes of a data: URI, or None."""
    if len(href) < 5 or href[:4].lower() != "data" or href[4] != ':':
        return None
    j = href.find(',')
    if j < 0:
        return None
    payload, out = href[j + 1:], bytearray()
    if j >= 7 and href[j - 7:j].lower() == ";base64":
        bits = count = 0
        alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        for ch in payload:
            if ch == '=':
                break
            if ord(ch) <= 32:
                continue
            v = alphabet.find(ch)
            if v < 0:
                break
            bits, count = bits << 6 | v, count + 6
            if count >= 8:
                count -= 8
                out.append(bits >> count & 255)
                bits &= (1 << count) - 1
        return bytes(out)
    i = 0
    while i < len(payload):
        ch = payload[i]
        i += 1
        if ch == '%' and i + 2 <= len(payload) and all(c in "0123456789abcdefABCDEF" for c in payload[i:i + 2]):
            out.append(int(payload[i:i + 2], 16))
            i += 2
        else:
            out.append(ord(ch) & 255)
    return bytes(out)


FE_WORDS = {"feFlood": 1, "feOffset": 2, "feGaussianBlur": 3, "feMerge": 4, "feBlend": 5, "feComposite": 6,
            "feColorMatrix": 7, "feComponentTransfer": 8, "feMorphology": 9, "feTile": 10, "feDropShadow": 11,
            "feMergeNode": 12, "feFuncR": 13, "feFuncG": 14, "feFuncB": 15, "feFuncA": 16, "feTurbulence": 17,
            "feImage": 18, "feConvolveMatrix": 19, "feDisplacementMap": 20, "feDiffuseLighting": 21,
            "feSpecularLighting": 22, "feDistantLight": 23, "fePointLight": 24, "feSpotLight": 25}
FE_NEWER_TYPES = {17: 12, 18: 15, 19: 10, 20: 11, 21: 13, 22: 14}
FE_Q_DEFAULTS = {17: [0.0, 0.0, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0], 18: [0.0] * 8,
                 19: [3.0, 3.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0], 20: [0.0, 0.0, 3.0, 3.0, 0.0, 0.0, 0.0, 0.0],
                 21: [1.0, 1.0, 1.0, 0.0, 4294967295.0, 0.0, 0.0, 0.0],
                 22: [1.0, 1.0, 1.0, 0.0, 4294967295.0, 0.0, 0.0, 0.0]}
# svg_fe_q_attrs: name -> (codes from, to, q slot, kind, given bit)
FE_Q_ATTRS = {"baseFrequency": (17, 17, 0, "pair", 0), "numOctaves": (17, 17, 2, "number", 0),
              "seed": (17, 17, 3, "number", 0), "stitchTiles": (17, 17, 4, ["noStitch", "stitch"], 0),
              "order": (19, 19, 0, "pair", 0), "kernelMatrix": (19, 19, 0, "text", 0),
              "divisor": (19, 19, 2, "number", 8), "bias": (19, 19, 3, "number", 0),
              "targetX": (19, 19, 4, "number", 9), "targetY": (19, 19, 5, "number", 10),
              "edgeMode": (19, 19, 6, ["duplicate", "wrap", "none"], 0),
              "preserveAlpha": (19, 19, 7, ["false", "true"], 0), "scale": (20, 20, 0, "twice", 0),
              "xChannelSelector": (20, 20, 2, ["R", "G", "B", "A"], 0),
              "yChannelSelector": (20, 20, 3, ["R", "G", "B", "A"], 0),
              "surfaceScale": (21, 22, 0, "number", 0), "diffuseConstant": (21, 21, 1, "number", 0),
              "specularConstant": (22, 22, 1, "number", 0), "specularExponent": (22, 22, 2, "number", 0),
              "lighting-color": (21, 22, 4, "colour", 0)}
DEG = 0.017453292519943295
FE_KEYWORDS = {"SourceGraphic": -1, "SourceAlpha": -2, "BackgroundImage": -3, "BackgroundAlpha": -3,
               "FillPaint": -3, "StrokePaint": -3}
FE_MODES = ["normal", "multiply", "screen", "darken", "lighten"]
FE_OPERATORS = ["over", "in", "out", "atop", "xor", "arithmetic"]
CM_IDENT = [1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]
CM_LUM = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.2125, 0.7154, 0.0721, 0.0, 0.0]
CM_ALPHA = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]
CM_SAT_A = [0.213, 0.715, 0.072, 0.0, 0.0, 0.213, 0.715, 0.072, 0.0, 0.0, 0.213, 0.715, 0.072, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0]
CM_SAT_B = [0.787, -0.715, -0.072, 0.0, 0.0, -0.213, 0.285, -0.072, 0.0, 0.0, -0.213, -0.715, 0.928, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
CM_HUE_C = [-0.213, -0.715, 0.928, 0.0, 0.0, 0.143, 0.14, -0.283, 0.0, 0.0, -0.787, 0.715, 0.072, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


@dataclass
class Filter:
    units: int = 1                                  # filterUnits: 1 objectBoundingBox
    prim_units: int = 0
    linear: int = 1
    region: list = field(default_factory=lambda: [0.0] * 4)
    prims: list = field(default_factory=list)       # dicts (svg_filter_compile's UgfxSvgFe)


def numbers(v):
    out, i = [], 0
    while v is not None:
        n, i = number(v, i)
        if n is None:
            break
        out.append(n)
    return out


def fe_cif(v):
    t = trim(v)
    return {"sRGB": 0, "linearRGB": 1, "auto": 0}.get(t)


def fe_length(v, axis, obb, st):
    """svg_fe_length."""
    if not obb:
        val, _ = length(v, "x" if axis == 0 else "y", st)
        return val if val is not None else 0.0
    val, j = number(v, 0)
    if val is None:
        return 0.0
    if j < len(v) and v[j] == '%':
        val = val * 0.01
    return val


def filter_compile(el, st, image_fn=None):
    """svg_filter_compile."""
    f = Filter()
    raw = ["-10%", "-10%", "120%", "120%"]
    for name, value in el.attrib.items():
        name = name.split('}')[-1]
        if name in ("x", "y", "width", "height"):
            raw[("x", "y", "width", "height").index(name)] = value
        elif name == "color-interpolation-filters":
            c = fe_cif(value)
            if c is not None:
                f.linear = c
        elif name == "filterUnits":
            f.units = int(trim(value) == "objectBoundingBox")
        elif name == "primitiveUnits":
            f.prim_units = int(trim(value) == "objectBoundingBox")
    f.region = [fe_length(v, i % 2, f.units, st) for i, v in enumerate(raw)]
    for child in el:
        code = FE_WORDS.get(child.tag.split('}')[-1])
        if code is None or 12 <= code <= 16 or code >= 23 or len(f.prims) >= 16:
            continue
        p = fe_begin(f, child, code)
        funcs = [[0.0, 1.0, 0.0, 1.0, 1.0, 0.0, 0.0] for _ in range(4)]
        tables, merge = [None] * 4, []
        for sub in child:
            c = FE_WORDS.get(sub.tag.split('}')[-1])
            if c == 12:
                inp = -4
                for name, value in sub.attrib.items():
                    if name.split('}')[-1] == "in":
                        inp = fe_input(f, len(f.prims) - 1, trim(value))
                if len(merge) < 16:
                    merge.append(float(len(f.prims) - 2 if inp == -4 else inp))
            elif c is not None and c >= 23:
                fe_light(p, sub, c)
            elif c is not None and 13 <= c <= 16:
                ch = c - 13
                for name, value in sub.attrib.items():
                    name = name.split('}')[-1]
                    if name == "type":
                        t = trim(value)
                        if t in ("identity", "table", "discrete", "linear", "gamma"):
                            funcs[ch][0] = float(("identity", "table", "discrete", "linear", "gamma").index(t))
                    elif name == "tableValues":
                        tables[ch] = value
                    elif name in ("slope", "intercept", "amplitude", "exponent", "offset"):
                        n, _ = number(value, 0)
                        if n is not None:
                            funcs[ch][("slope", "intercept", "amplitude", "exponent", "offset").index(name) + 1] = n
        fe_finish(f, p, st, funcs, tables, merge, image_fn)
    return f


def fe_light(p, el, c):
    """svg_fe_child's lights: the first, in a lighting primitive."""
    if p["light_type"] or p["code"] < 21:
        return
    p["light_type"] = c - 22
    for name, value in el.attrib.items():
        name = name.split('}')[-1]
        if c == 23:
            slot = {"azimuth": 0, "elevation": 1}.get(name)
        else:
            slot = {"x": 0, "y": 1, "z": 2}.get(name)
            if slot is None and c == 25:
                slot = {"pointsAtX": 3, "pointsAtY": 4, "pointsAtZ": 5, "specularExponent": 6,
                        "limitingConeAngle": 7}.get(name)
        if slot is None:
            continue
        n, _ = number(value, 0)
        if n is None:
            continue
        p["light"][slot] = n
        if slot == 7:
            p["cone"] = 1


def fe_input(f, idx, v):
    if v in FE_KEYWORDS:
        return FE_KEYWORDS[v]
    for i in range(idx - 1, -1, -1):
        if f.prims[i]["name"] is not None and f.prims[i]["name"] == v:
            return i
    return -4


def fe_begin(f, el, code):
    p = dict(code=code, type=0, in1=-4, in2=-4, linear=f.linear, given=set(), sub=[0.0] * 4, raw=[None] * 4,
             std=[0.0, 0.0], dxy=[0.0, 0.0], radius=[0.0, 0.0], k=[0.0] * 4, op=0, cm_type=0, flood=0xFF000000,
             flood_op=1.0, values=None, var=[], name=None, q=list(FE_Q_DEFAULTS.get(code, [0.0] * 8)),
             light=[0.0] * 6 + [1.0, 0.0], light_type=0, cone=0, par=(5, 0), image=None)
    f.prims.append(p)
    idx = len(f.prims) - 1
    for name, value in el.attrib.items():
        name = name.split('}')[-1]
        if name in ("in", "in2"):
            p["in1" if name == "in" else "in2"] = fe_input(f, idx, trim(value))
        elif name == "result":
            p["name"] = trim(value)
        elif name in ("x", "y", "width", "height"):
            i = ("x", "y", "width", "height").index(name)
            p["given"].add(i)
            p["raw"][i] = value
        elif name == "color-interpolation-filters":
            c = fe_cif(value)
            if c is not None:
                p["linear"] = c
        elif name in ("stdDeviation", "radius"):
            key = "std" if name == "stdDeviation" else "radius"
            p["given"].add(4 if key == "std" else 7)
            v1, i = number(value, 0)
            if v1 is None:
                continue
            p[key] = [v1, v1]
            v2, _ = number(value, i)
            if v2 is not None:
                p[key][1] = v2
        elif name in ("dx", "dy"):
            p["given"].add(5 if name == "dx" else 6)
            n, _ = number(value, 0)
            if n is not None:
                p["dxy"][0 if name == "dx" else 1] = n
        elif name == "flood-color":
            kind, c = colour(value)
            if kind == "colour":
                p["flood"] = c
        elif name == "flood-opacity":
            n, j = number(value, 0)
            if n is not None:
                if j < len(value) and value[j] == '%':
                    n = n * 0.01
                p["flood_op"] = min(max(n, 0.0), 1.0)
        elif name == "mode":
            t = trim(value)
            if t in FE_MODES:
                p["op"] = FE_MODES.index(t)
        elif name == "operator":
            t = trim(value)
            if t in FE_OPERATORS:
                p["op"] = FE_OPERATORS.index(t)
            elif t in ("erode", "dilate"):
                p["op"] = int(t == "dilate")
        elif name in ("k1", "k2", "k3", "k4"):
            n, _ = number(value, 0)
            if n is not None:
                p["k"][int(name[1]) - 1] = n
        elif name == "type":
            t = trim(value)
            if code == 17:
                if t in ("fractalNoise", "turbulence"):
                    p["q"][5] = float(("fractalNoise", "turbulence").index(t))
            elif t in ("matrix", "saturate", "hueRotate", "luminanceToAlpha"):
                p["cm_type"] = ("matrix", "saturate", "hueRotate", "luminanceToAlpha").index(t)
        elif name == "values":
            p["values"] = value
        elif name in ("href", "xlink:href", "preserveAspectRatio"):
            if code == 18:
                if name == "preserveAspectRatio":
                    p["par"] = par(value)
                else:
                    p["values"] = value
        elif name in FE_Q_ATTRS:
            lo, hi, slot, kind, bit = FE_Q_ATTRS[name]
            if not lo <= code <= hi:
                continue
            if kind == "pair":
                v1, i = number(value, 0)
                if v1 is None:
                    continue
                p["q"][slot] = p["q"][slot + 1] = v1
                v2, _ = number(value, i)
                if v2 is not None:
                    p["q"][slot + 1] = v2
            elif kind == "text":
                p["values"] = value
            elif kind == "colour":
                k, c = colour(value)
                if k == "colour":
                    p["q"][slot] = float(c)
            elif isinstance(kind, list):
                t = trim(value)
                if t in kind:
                    p["q"][slot] = float(kind.index(t))
            else:
                n, _ = number(value, 0)
                if n is None:
                    continue
                p["q"][slot] = n
                if kind == "twice":
                    p["q"][slot + 1] = n
                if bit:
                    p["given"].add(bit)
    return p


def fe_whole(v):
    """svg_fe_whole: an int, or None."""
    if v != v or not -1048576.0 < v < 1048576.0 or float(int(v)) != v:
        return None
    return int(v)


def fe_kernel(p):
    """svg_fe_kernel."""
    ox, oy = fe_whole(p["q"][0]), fe_whole(p["q"][1])
    ok = ox is not None and oy is not None and 1 <= ox <= 64 and 1 <= oy <= 64
    vals = numbers(p["values"]) if ok else []
    if ok:
        ok = len(vals) == ox * oy
    for bit, slot, order in ((9, 4, ox), (10, 5, oy)):
        if not ok:
            break
        if bit in p["given"]:
            t = fe_whole(p["q"][slot])
            ok = t is not None and 0 <= t < order
        else:
            p["q"][slot] = float(order >> 1)
    if not ok:
        p["type"], p["dxy"] = 1, [0.0, 0.0]
        return
    p["var"] = vals
    if not (8 in p["given"] and p["q"][2] != 0):
        s = 0.0
        for v in vals:
            s = s + v
        p["q"][2] = s if s != 0 else 1.0


def fe_image(p, image_fn):
    """svg_fe_image."""
    href = p["values"]
    got = None
    if image_fn is not None and href is not None:
        data = data_uri(href)
        got = image_fn(data, 0) if data is not None else image_fn(href, 1)
    if got is None or not (got[0] > 0 and got[1] > 0):
        p["type"], p["flood"] = 0, 0
        return
    p["image"] = got


def fe_finish(f, p, st, funcs, tables, merge, image_fn=None):
    idx = f.prims.index(p)
    for key in ("in1", "in2"):
        if p[key] == -4:
            p[key] = idx - 1
    for i in range(4):
        if i in p["given"]:
            p["sub"][i] = fe_length(p["raw"][i], i % 2, f.prim_units, st)
    a = int((p["flood"] >> 24) * p["flood_op"] + 0.5)
    p["flood"] = a << 24 | (p["flood"] & 0xFFFFFF)
    code = p["code"]
    if code == 11:
        fe_shadow(f, p, idx)
        return
    if code in FE_NEWER_TYPES:
        t = p["type"] = FE_NEWER_TYPES[code]
        if t == 10:
            fe_kernel(p)
        elif t == 15:
            fe_image(p, image_fn)
        elif t == 12:
            p["var"] = [0.0] * 10
        elif t in (13, 14):
            if p["light_type"]:
                p["var"] = [0.0] * 6
            else:
                p["type"], p["flood"] = 0, 0
        return
    if code > 10:
        p["type"], p["flood"] = 0, 0
        return
    p["type"] = code - 1
    if p["type"] == 3:
        p["var"] = list(merge)
    elif p["type"] == 6:
        vals = numbers(p["values"])[:20]
        if p["cm_type"] == 1:
            s = vals[0] if vals else 1.0
            p["var"] = [b * s + a_ for a_, b in zip(CM_SAT_A, CM_SAT_B)]
        elif p["cm_type"] == 2:
            ang = (vals[0] if vals else 0.0) * 0.017453292519943295
            c, sn = math.cos(ang), math.sin(ang)
            p["var"] = [b * c + a_ + cc * sn for a_, b, cc in zip(CM_SAT_A, CM_SAT_B, CM_HUE_C)]
        elif p["cm_type"] == 3:
            p["var"] = list(CM_LUM)
        else:
            p["var"] = vals if len(vals) == 20 else list(CM_IDENT)
    elif p["type"] == 7:
        var = []
        for ch in range(4):
            t = numbers(tables[ch])
            row = list(funcs[ch])
            row[6] = float(len(t))
            var += row + t
        p["var"] = var


def fe_shadow(f, p, k):
    """svg_fe_shadow: six primitives."""
    if len(f.prims) + 5 > 16:
        p["type"], p["flood"] = 0, 0
        return
    if 4 not in p["given"]:
        p["std"] = [2.0, 2.0]
    if 5 not in p["given"]:
        p["dxy"][0] = 2.0
    if 6 not in p["given"]:
        p["dxy"][1] = 2.0
    name, src = p["name"], p["in1"]
    copies = []
    for _ in range(5):
        q = dict(p)
        q["std"], q["dxy"], q["radius"], q["k"] = list(p["std"]), list(p["dxy"]), list(p["radius"]), list(p["k"])
        q["name"] = None
        copies.append(q)
    p["name"] = None
    copies[-1]["name"] = name
    f.prims[k + 1:k + 1] = copies
    p["type"], p["var"] = 6, list(CM_ALPHA)
    copies[0].update(type=2, in1=k)
    copies[1].update(type=1, in1=k + 1)
    copies[2].update(type=0)
    copies[3].update(type=5, in1=k + 3, in2=k + 2, op=1)
    copies[4].update(type=3, var=[float(k + 4), float(src)])


def _div(a, b):
    """IEEE division (divsd)."""
    if b == 0:
        if a == 0 or a != a:
            return math.nan
        return math.copysign(math.inf, a) * math.copysign(1.0, b)
    return a / b


def _floor(v):
    if v != v:
        return 0
    v = min(max(v, -1073741824.0), 1073741824.0)
    return math.floor(v)


def filter_device(f, item, t):
    """svg_filter_device -> (region, prims) for ugfx_ctx_filter."""
    m = mul(t, item.matrix)
    bx, by = item.bbox[0], item.bbox[1]
    bw, bh = item.bbox[2] - bx, item.bbox[3] - by
    sx = math.sqrt(m[0] * m[0] + m[1] * m[1])
    sy = math.sqrt(m[2] * m[2] + m[3] * m[3])

    def units(r, obb):
        if not obb:
            return list(r)
        return [r[0] * bw + bx, r[1] * bh + by, r[2] * bw, r[3] * bh]

    def device(r):
        xs, ys = [], []
        for cx, cy in ((r[0], r[1]), (r[0] + r[2], r[1]), (r[0], r[1] + r[3]), (r[0] + r[2], r[1] + r[3])):
            xs.append(m[0] * cx + m[2] * cy + m[4])
            ys.append(m[1] * cx + m[3] * cy + m[5])
        x0, y0, x1, y1 = xs[0], ys[0], xs[0], ys[0]
        for x, y in zip(xs[1:], ys[1:]):
            x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
        return (_floor(x0), _floor(y0), -_floor(0.0 - x1), -_floor(0.0 - y1))

    def lengths(v):
        a, b = v
        if f.prim_units:
            a, b = a * bw, b * bh
        return [a * sx, b * sy]

    reg_user = units(f.region, f.units)
    out = []
    for p in f.prims:
        u = units(p["sub"], f.prim_units)
        u = [u[i] if i in p["given"] else reg_user[i] for i in range(4)]
        q = [0.0] * 8
        t_ = p["type"]
        if t_ == 0:
            q[0] = float(p["flood"])
        elif t_ == 2:
            q[0], q[1] = lengths(p["std"])
        elif t_ == 8:
            q[0] = float(p["op"])
            q[1], q[2] = lengths(p["radius"])
        elif t_ == 1:
            dx, dy = p["dxy"]
            if f.prim_units:
                dx, dy = dx * bw, dy * bh
            q[0] = m[0] * dx + m[2] * dy
            q[1] = m[1] * dx + m[3] * dy
        elif t_ >= 10:
            q = list(p["q"])
            var = list(p["var"])
            if t_ == 11:
                q[0], q[1] = lengths(p["q"][0:2])
            elif t_ == 12:
                tile = list(u)
                tm = m
                if f.prim_units:
                    tile = [_div(u[0] - bx, bw), _div(u[1] - by, bh), _div(u[2], bw), _div(u[3], bh)]
                    tm = mul(m, [bw, 0.0, 0.0, bh, bx, by])
                inv = invert(tm)
                var = (inv if inv is not None else [0.0] * 6) + tile
            elif t_ == 15:
                iw, ih, img = p["image"]
                if u[2] > 0 and u[3] > 0:
                    fm = fit([0.0, 0.0, float(iw), float(ih)], u[2], u[3], p["par"])
                    x0, y0 = u[0] + fm[4], u[1] + fm[5]
                    x1, y1 = float(iw) * fm[0] + x0, float(ih) * fm[3] + y0
                    X0, Y0 = m[0] * x0 + m[2] * y0 + m[4], m[1] * x0 + m[3] * y0 + m[5]
                    X1, Y1 = m[0] * x1 + m[2] * y1 + m[4], m[1] * x1 + m[3] * y1 + m[5]
                    q[0], q[2] = min(X0, X1), max(X0, X1) - min(X0, X1)
                    q[1], q[3] = min(Y0, Y1), max(Y0, Y1) - min(Y0, Y1)
                var = [float(iw), float(ih)] + [float(v) for v in (img.reshape(-1) if hasattr(img, "reshape") else img)]
            elif t_ in (13, 14):
                light = p["light"]
                q[3] = float(p["light_type"] - 1)
                q[5] = light[6]
                q[6] = math.cos(abs(light[7]) * DEG) if p["cone"] else -2.0
                if p["light_type"] == 1:
                    el = light[1] * DEG
                    ce = math.cos(el)
                    lz = math.sin(el)
                    az = light[0] * DEG
                    lx = math.cos(az) * ce
                    ly = math.sin(az) * ce
                    dx = m[0] * lx + m[2] * ly
                    dy = m[1] * lx + m[3] * ly
                    n = math.sqrt(dx * dx + dy * dy)
                    h = math.sqrt(lx * lx + ly * ly)
                    if n > 0:
                        k = h / n
                        dx, dy = dx * k, dy * k
                    var = [dx, dy, lz, 0.0, 0.0, 0.0]
                else:
                    var = []
                    for x, y, z in (light[0:3], light[3:6]):
                        if f.prim_units:
                            x, y = x * bw + bx, y * bh + by
                            z = z * math.sqrt((bw * bw + bh * bh) * 0.5)
                        var += [m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5], z * ((sx + sy) * 0.5)]
        else:
            q[0] = float(p["op"])
            q[1:5] = p["k"]
        if t_ < 10:
            var = list(p["var"])
        out.append(dict(type=t_, in1=p["in1"], in2=p["in2"], linear=p["linear"], sub=device(u), p=q,
                        var=var))
    return device(reg_user), out


@dataclass
class Group:
    kind: str                                       # "begin" / "end"
    alpha: int = 255
    clip: object = None                             # Clip
    matrix: list = None                             # the element's (begin)
    bbox: list = None                               # its content's bounds in its space
    mask: object = None                             # Mask
    begin: object = None                            # an end's begin
    filter: object = None                           # Filter


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
        if not isinstance(it, (Item, ImageItem)):
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


CSS_IDENT = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
CSS_PSEUDO = {"first-child": 5, "last-child": 6, "root": 7, "nth-child": 8, "nth-last-child": 9, "only-child": 10}
CSS_OPS = {"=": 1, "~=": 2, "|=": 3, "^=": 4, "$=": 5, "*=": 6}


def _css_run(t, i):
    while i < len(t) and t[i] in CSS_IDENT:
        i += 1
    return i


def _css_ws(t, i):
    while i < len(t) and ord(t[i]) <= 32:
        i += 1
    return i


def _css_digits(t, i):
    j = i
    while j < len(t) and '0' <= t[j] <= '9':
        j += 1
    if j == i or j - i > 6:
        return None, i
    return int(t[i:j]), j


def css_nth(t):
    """an+b inside :nth-child() -> (a, b), or None."""
    t = trim(t)
    if t == "odd":
        return 2, 1
    if t == "even":
        return 2, 0
    i, sign = 0, 1
    if i < len(t) and t[i] in "+-":
        sign = -1 if t[i] == '-' else 1
        i += 1
    num, j = _css_digits(t, i)
    if num is None and j != i:
        return None
    i = j
    if i < len(t) and t[i] in "nN":
        a = sign * (1 if num is None else num)
        i = _css_ws(t, i + 1)
        if i == len(t):
            return a, 0
        if t[i] not in "+-":
            return None
        s = -1 if t[i] == '-' else 1
        i = _css_ws(t, i + 1)
        b, i = _css_digits(t, i)
        if b is None or i != len(t):
            return None
        return a, s * b
    if num is None or i != len(t):
        return None
    return 0, sign * num


def css_compile(sel):
    """One selector -> (specificity, simples) or None when not supported. A simple is (kind, op, new
    compound, combinator to the one before, name, value, a, b): kinds 1 type, 2 class, 3 id, 4 attribute,
    5 first-child, 6 last-child, 7 root, 8 nth-child, 9 nth-last-child, 10 only-child, 12 *; combinators
    1 descendant, 2 child, 3 next sibling, 4 later sibling."""
    simples, spec, i, n, new, comb = [], 0, 0, len(sel), True, 0
    while i < n:
        c = sel[i]
        if ord(c) <= 32 or c in ">+~":
            if new:
                return None
            i = _css_ws(sel, i)
            comb = 1
            if i < n and sel[i] in ">+~":
                comb = ">+~".index(sel[i]) + 2
                i = _css_ws(sel, i + 1)
            new = True
            continue
        op, name, value, a, b = 0, None, None, 0, 0
        if c == '*' or c in CSS_IDENT:
            if not new:
                return None
            if c == '*':
                kind, i = 12, i + 1
            else:
                j = _css_run(sel, i)
                kind, name, i = 1, sel[i:j], j
                spec += 1
        elif c in ".#":
            j = _css_run(sel, i + 1)
            if j == i + 1:
                return None
            kind, name, i = (2 if c == '.' else 3), sel[i + 1:j], j
            spec += 100 if c == '.' else 10000
        elif c == '[':
            i = _css_ws(sel, i + 1)
            j = _css_run(sel, i)
            if j == i:
                return None
            name, i = sel[i:j], _css_ws(sel, j)
            kind = 4
            if i < n and sel[i] == ']':
                i += 1
            else:
                if sel[i:i + 1] == '=':
                    op, i = 1, i + 1
                elif sel[i:i + 2] in CSS_OPS:
                    op, i = CSS_OPS[sel[i:i + 2]], i + 2
                else:
                    return None
                i = _css_ws(sel, i)
                if i < n and sel[i] in "\"'":
                    j = sel.find(sel[i], i + 1)
                    if j < 0:
                        return None
                    value, i = sel[i + 1:j], j + 1
                else:
                    j = _css_run(sel, i)
                    if j == i:
                        return None
                    value, i = sel[i:j], j
                i = _css_ws(sel, i)
                if i >= n or sel[i] != ']':
                    return None
                i += 1
            spec += 100
        elif c == ':':
            j = _css_run(sel, i + 1)
            kind = CSS_PSEUDO.get(sel[i + 1:j])
            if kind is None:
                return None
            i = j
            if kind in (8, 9):
                if i >= n or sel[i] != '(':
                    return None
                j = sel.find(')', i + 1)
                if j < 0:
                    return None
                ab = css_nth(sel[i + 1:j])
                if ab is None:
                    return None
                (a, b), i = ab, j + 1
            spec += 100
        else:
            return None
        simples.append((kind, op, new, comb, name, value, a, b))
        new, comb = False, 0
        if len(simples) > 32:
            return None
    if new or sum(1 for x in simples if x[2]) > 16:
        return None
    return spec, simples


def css_rules(text):
    """The supported rules of a style sheet: (specificity, simples, declarations)."""
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
            got = css_compile(sel)
            if got is not None:
                rules.append((got[0], got[1], decls))
    return rules


class CssTree:
    """The document's elements: parents and siblings (ugfx_svg_defs_scan's element table)."""

    def __init__(self, root):
        self.parent, self.kids = {root: None}, {}
        for p in root.iter():
            kids = list(p)
            self.kids[p] = kids
            for c in kids:
                self.parent[c] = p

    def siblings(self, el):
        p = self.parent.get(el)
        return [el] if p is None else self.kids[p]


def _css_nth_ok(a, b, i):
    if a == 0:
        return i == b
    d = i - b
    return d % a == 0 and d // a >= 0


def _css_simple(s, el, tree):
    kind, op, _, _, name, value, a, b = s
    if kind == 12:
        return True
    if kind == 1:
        return el.tag.split('}')[-1] == name
    if kind == 2:
        return name in re.split(r"[\x00- ]+", el.attrib.get("class", ""))
    if kind == 3:
        return el.attrib.get("id") == name
    if kind == 4:
        v = el.attrib.get(name)
        if v is None:
            return False
        if op == 0:
            return True
        if op == 1:
            return v == value
        if op == 2:
            return value != "" and all(ord(ch) > 32 for ch in value) and value in re.split(r"[\x00- ]+", v)
        if op == 3:
            return v == value or v.startswith(value + "-")
        if value == "":
            return False
        return v.startswith(value) if op == 4 else v.endswith(value) if op == 5 else value in v
    if kind == 7:
        return tree.parent.get(el) is None
    sib = tree.siblings(el)
    k = sib.index(el)
    if kind == 5:
        return k == 0
    if kind == 6:
        return k == len(sib) - 1
    if kind == 10:
        return len(sib) == 1
    if kind == 8:
        return _css_nth_ok(a, b, k + 1)
    return _css_nth_ok(a, b, len(sib) - k)


def css_match(simples, end, el, tree):
    """Do simples[:end] (whose last compound ends at end) match el?"""
    start = end - 1
    while not simples[start][2]:
        start -= 1
    if not all(_css_simple(s, el, tree) for s in simples[start:end]):
        return False
    if start == 0:
        return True
    comb = simples[start][3]
    if comb in (1, 2):
        p = tree.parent.get(el)
        while p is not None:
            if css_match(simples, start, p, tree):
                return True
            if comb == 2:
                return False
            p = tree.parent.get(p)
        return False
    sib = tree.siblings(el)
    k = sib.index(el)
    for j in range(k - 1, -1, -1):
        if css_match(simples, start, sib[j], tree):
            return True
        if comb == 3:
            return False
    return False


def trim(v):
    v = v.strip(" \t\r\n")
    if len(v) >= 10 and v[-10] == '!':
        v = v[:-10].strip(" \t\r\n")
    return v


def parse(text, image_fn=None, font_fn=None, shape_fn=None):
    """image_fn(bytes or href, kind) -> (width, height, image) or None, as ugfx_svg_parse_ex's;
    font_fn((family, weight, style), code point, size, outline) -> (advance, path);
    shape_fn((family, weight, style), code points, size) -> [(glyph key, cluster, advance,
    x offset, y offset down)] or None: text runs shaped (ugfx's UgfxSvg_shape_fn)."""
    import xml.etree.ElementTree as ET
    root = ET.fromstring(text)
    doc = Doc()
    grads = scan_gradients(root)
    rules = []
    for el in root.iter():
        if el.tag.split('}')[-1] == "style" and el.text:
            rules += css_rules(el.text)
    rules.sort(key=lambda r: r[0])                 # stable: document order within a specificity
    tree = CssTree(root)
    ids = {}
    for el in root.iter():
        if "id" in el.attrib:
            ids.setdefault(trim(el.attrib["id"]), el)
    default = dict(m=[1.0, 0, 0, 1.0, 0, 0], fill=("colour", 0xFF000000), stroke=("none", 0xFF000000),
                   fill_op=1.0, stroke_op=1.0, op=1.0, sw=1.0, miter=4.0, join=0, cap=0, rule=0, skip=False,
                   font=16.0, vw=300.0, vh=150.0, color=None, hidden=False, order=0, dash=None, dash_off=0.0,
                   cliprule=0, m0=None, m1=None, m2=None, family=None, weight=400, fstyle=0, anchor=0,
                   intext=0, lspace=0.0, wspace=0.0, preserve=0, lists=(None,) * 5, bshift=0.0, dbase=0,
                   tpath=0, decor=(None, None, None))
    tx = {}                                         # the text layout (one text element at a time)
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

    def text_lists(st, el, lists_raw):
        """svg_text_lists: x, y, dx, dy, rotate as (values, first character)."""
        raws = [el.attrib.get("x"), el.attrib.get("y"), lists_raw.get("dx"), lists_raw.get("dy"),
                lists_raw.get("rotate")]
        lists = list(st["lists"])
        for k, v in enumerate(raws):
            if v is None:
                continue
            vals, i = [], 0
            while True:
                if k == 4:
                    val, j = number(v, i)
                else:
                    val, _, j = length_at(v, i, "x" if k % 2 == 0 else "y", st)
                if val is None:
                    break
                vals.append(val)
                i = j
            lists[k] = (vals, tx["count"])
        st["lists"] = tuple(lists)

    def list_value(st, k, c):
        rec = st["lists"][k]
        if rec is None or not 0 <= c - rec[1] < len(rec[0]):
            return None
        return rec[0][c - rec[1]]

    run = {"cps": [], "st": None}

    def text_node(s, st, uses):
        for ch in s:
            text_cp(ord(ch), st, uses)
        text_flush(uses)

    def positioned(st, c):
        """Does the character have its own x, y, dx, dy or rotate value (it starts a run)."""
        if any(list_value(st, k, c) is not None for k in range(4)):
            return True
        rec = st["lists"][4]
        return rec is not None and 0 <= c - rec[1] < len(rec[0])

    def text_put(cp, st, uses):
        """svg_text_put: without shaping placed at once, else into the run."""
        if shape_fn is None or font_fn is None:
            text_char(cp, st, uses)
            return
        if run["cps"] and positioned(st, tx["count"] + len(run["cps"])):
            text_flush(uses)
        run["cps"].append(cp)
        run["st"] = st

    def text_flush(uses):
        """svg_text_flush: the run shaped, its glyphs placed."""
        cps, st = run["cps"], run["st"]
        run["cps"] = []
        if not cps:
            return
        glyphs = shape_fn((st["family"], st["weight"], st["fstyle"]), cps, st["font"])
        if glyphs is None:
            for cp in cps:
                text_char(cp, st, uses)
            return
        start = tx["count"]
        for i, (key, cl, adv, xo, yo) in enumerate(glyphs):
            nxt = glyphs[i + 1][1] if i + 1 < len(glyphs) else len(cps)
            nch = nxt - cl if nxt != cl else 0
            spaces = sum(1 for c in cps[cl:cl + nch] if c == 32)
            blank = nch == 1 and cps[cl] == 32
            tx["count"] = start + cl
            text_char(key, st, uses, (adv, xo, yo, nch, spaces, i == 0, blank))
        tx["count"] = start + len(cps)

    def text_cp(cp, st, uses):
        """svg_text_cp: white space, then the character."""
        if cp in (32, 9, 10, 13):
            if st["preserve"]:
                tx["any"] = 1
                text_put(32, st, uses)
            elif tx["any"]:
                tx["space"] = 1
            return
        if tx["space"]:
            tx["space"] = 0
            text_put(32, st, uses)
        tx["any"] = 1
        text_put(cp, st, uses)

    def text_char(cp, st, uses, g=None):
        """svg_text_char; g = a shaped glyph (advance, x offset, y offset, characters, spaces,
        first of its run, blank) with cp its key."""
        if font_fn is None:
            return
        c = tx["count"]
        if g is None or g[5]:
            v = list_value(st, 0, c)
            if v is not None:
                text_finish()
                tx["x"] = v
            v = list_value(st, 1, c)
            if v is not None and not tx["onpath"]:
                text_finish()
                tx["y"] = v
            v = list_value(st, 2, c)
            if v is not None:
                tx["x"] = v + tx["x"]
            v = list_value(st, 3, c)
            if v is not None:
                tx["y"] = v + tx["y"]
        rot, rec = 0.0, st["lists"][4]
        if rec is not None and rec[0]:
            i = c - rec[1]
            rot = rec[0][i if i < len(rec[0]) else len(rec[0]) - 1] * 0.017453292519943295
        if not tx["chunk"]:
            tx.update(chunk=len(doc.items) + 1, cx=tx["x"], anchor=st["anchor"], chunkpath=tx["onpath"])
        font = (st["family"], st["weight"], st["fstyle"])
        s = st["font"]
        if g is None:
            adv, _ = font_fn(font, cp, s, False)
        else:
            adv = g[0]
        asc, desc = font_fn(font, -1, s, False)
        if not asc > 0:
            asc, desc = s * 0.8, s * 0.2
        gy = (0.0, (asc - desc) * 0.5, (asc - desc) * 0.5, asc * 0.8, asc * 0.5, asc, 0.0 - desc)[st["dbase"]]
        gy = gy - st["bshift"]
        if g is None:
            x = tx["x"] + adv + st["lspace"]
            if cp == 32:
                x = x + st["wspace"]
        else:
            x = tx["x"] + adv + st["lspace"] * g[3] + st["wspace"] * g[4]
        step = x - tx["x"]
        y = tx["y"] + gy
        perp = tx["y"] - tx["y0"] + gy
        base = mul(st["m"], [1.0, 0.0, 0.0, 1.0, tx["x"], y])

        def emitted(first, r):
            if tx["onpath"]:
                for i in range(first, len(doc.items)):
                    tx["recs"].append((i, tx["x"], perp, adv, r))

        def decoration(k):
            dst = st["decor"][k]
            if dst is None:
                return
            t = s * 0.05
            centre = (desc * 0.5, 0.0 - asc, 0.0 - asc * 0.375)[k]
            d = dict(dst)
            d["m"] = list(base)
            first = len(doc.items)
            shape("decor", {"rect": (0.0, centre - t * 0.5, step, t)}, d, 1.0, {}, uses)
            emitted(first, 0.0)

        decoration(0)
        decoration(1)
        if (g is None and cp != 32) or (g is not None and not g[6]):
            _, path = font_fn(font, cp, s, True)
            gst = dict(st)
            cs, sn = math.cos(rot), math.sin(rot)
            gbase = base if g is None else mul(st["m"], [1.0, 0.0, 0.0, 1.0, tx["x"] + g[1], y + g[2]])
            gst["m"] = mul(gbase, [cs, sn, 0.0 - sn, cs, 0.0, 0.0])
            first = len(doc.items)
            shape("glyph", {"glyph": path}, gst, 1.0, {}, uses)
            emitted(first, rot)
        decoration(2)
        tx["x"] = x
        tx["count"] = c + 1

    def tp_points(target):
        """svg_textpath_points: a path element's outline as points (x, y, distance, starts a subpath)."""
        if target is None or target.tag.split('}')[-1] != "path":
            return None
        cmds = path_data(target.attrib.get("d", ""))
        tm = transform_list(target.attrib["transform"], [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]) \
            if "transform" in target.attrib else None
        if tm is None:
            tm = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0]
        raw, cur, start = [], (0.0, 0.0), (0.0, 0.0)
        for c in cmds:
            if c[0] == 'move':
                raw.append((c[1], c[2], 1))
                cur = start = (c[1], c[2])
            elif c[0] == 'line':
                raw.append((c[1], c[2], 0))
                cur = (c[1], c[2])
            elif c[0] in ('quad', 'cubic'):
                for i in range(1, TP_STEPS + 1):
                    t = i / TP_STEPS
                    mt = 1.0 - t
                    if c[0] == 'quad':
                        a, b, d = mt * mt, 2.0 * mt * t, t * t
                        px = a * cur[0] + b * c[1] + d * c[3]
                        py = a * cur[1] + b * c[2] + d * c[4]
                    else:
                        a, b, d, e = mt * mt * mt, 3.0 * mt * mt * t, 3.0 * mt * t * t, t * t * t
                        px = a * cur[0] + b * c[1] + d * c[3] + e * c[5]
                        py = a * cur[1] + b * c[2] + d * c[4] + e * c[6]
                    raw.append((px, py, 0))
                cur = (c[-2], c[-1])
            elif c[0] == 'close':
                raw.append((start[0], start[1], 0))
                cur = start
        pts, dist = [], 0.0
        for x, y, new in raw:
            px = tm[0] * x + tm[2] * y + tm[4]
            py = tm[1] * x + tm[3] * y + tm[5]
            if pts and not new:
                dx, dy = px - pts[-1][0], py - pts[-1][1]
                dist = dist + math.sqrt(dx * dx + dy * dy)
            pts.append((px, py, dist, new or not pts))
        return pts, dist

    def tp_at(pts, m):
        """svg_textpath_at: the point and direction at distance m, or None off the path."""
        if not 0.0 <= m <= pts[1]:
            return None
        p = pts[0]
        for k in range(1, len(p)):
            if p[k][3]:
                continue
            s0, s1 = p[k - 1][2], p[k][2]
            ln = s1 - s0
            if not ln > 0 or m > s1:
                continue
            f = (m - s0) / ln
            x0, y0 = p[k - 1][0], p[k - 1][1]
            dx, dy = p[k][0] - x0, p[k][1] - y0
            return x0 + dx * f, y0 + dy * f, dx / ln, dy / ln
        return None

    def textpath_start(st, href, el):
        """svg_textpath_start."""
        text_finish()
        pts = tp_points(ids.get(href) if href is not None else None)
        if pts is None or not pts[0]:
            st["skip"] = True
            return
        so, raw = 0.0, el.attrib.get("startOffset")
        if raw is not None:
            n, j = number(raw, 0)
            if n is not None and j < len(raw) and raw[j] == '%':
                so = n * 0.01 * pts[1]
            else:
                v, _ = length(raw, "x", st)
                if v is not None:
                    so = v
        tx.update(x=so, y0=tx["y"], onpath=pts)

    def textpath_end():
        """svg_textpath_end: the chunk placed; text goes on from where the path text ended."""
        text_finish()
        pts = tx["onpath"]
        tx["onpath"] = None
        if pts is None:
            return
        m = min(max(tx["x"], 0.0), pts[1])
        at = tp_at(pts, m)
        if at is not None:
            tx["x"], tx["y"] = at[0], at[1]

    def text_finish():
        """svg_text_finish: middle / end anchors shift the chunk's items."""
        if not tx.get("chunk"):
            return
        start, tx["chunk"] = tx["chunk"] - 1, 0
        shift = 0.0
        if tx["anchor"]:
            shift = tx["cx"] - tx["x"]
            if tx["anchor"] == 1:
                shift = shift * 0.5
        pts, tx["chunkpath"] = tx["chunkpath"], None
        if pts is not None:
            recs, tx["recs"] = tx["recs"], []
            for i, x, perp, adv, r in recs:
                it = doc.items[i]
                at = tp_at(pts, x + shift + adv * 0.5)
                if at is None:
                    it.path = []
                    continue
                px, py, c, s = at
                m = mul(mul(tx["m"], [c, s, 0.0 - s, c, px, py]), [1.0, 0.0, 0.0, 1.0, 0.0 - adv * 0.5, perp])
                it.matrix = mul(m, [math.cos(r), math.sin(r), 0.0 - math.sin(r), math.cos(r), 0.0, 0.0])
            return
        if not tx["anchor"]:
            return
        inv = invert(tx["m"])
        if inv is None:
            return
        d = mul(mul(tx["m"], [1.0, 0.0, 0.0, 1.0, shift, 0.0]), inv)
        for it in doc.items[start:]:
            if isinstance(it, (Item, ImageItem, MarkerItem)) or (isinstance(it, Group) and it.kind == "begin"):
                it.matrix = mul(d, it.matrix)

    def image(g, st, href):
        """svg_image."""
        if st["hidden"] or image_fn is None or href is None:
            return
        data = data_uri(href)
        got = image_fn(data, 0) if data is not None else image_fn(href, 1)
        if got is None:
            return
        iw, ih, img = got
        if not (iw > 0 and ih > 0):
            return
        x, y = g.get("x", 0.0), g.get("y", 0.0)
        w, h = g.get("width", float(iw)), g.get("height", float(ih))
        if not (w > 0 and h > 0):
            return
        p = par(g.get("preserveAspectRatio"))
        m = fit([0.0, 0.0, float(iw), float(ih)], w, h, p)
        dest = [x + m[4], y + m[5], float(iw) * m[0], float(ih) * m[3]]
        doc.items.append(ImageItem(list(st["m"]), [('rect', x, y, w, h)], img, dest, int(bool(p[1] and p[0])),
                                   int(255 * 1.0 * st["op"] + 0.5)))

    def marker_attrs(rec, el, st):
        """svg_marker_attrs."""
        raw, vb, mpar = ["0", "0", "3", "3"], None, (5, 0)
        for name, value in el.attrib.items():
            name = name.split('}')[-1]
            if name in ("refX", "refY", "markerWidth", "markerHeight"):
                raw[("refX", "refY", "markerWidth", "markerHeight").index(name)] = value
            elif name == "markerUnits":
                rec.units = int(trim(value) == "userSpaceOnUse")
            elif name == "overflow":
                rec.clip = int(trim(value) not in ("visible", "auto"))
            elif name == "preserveAspectRatio":
                mpar = par(value)
            elif name == "orient":
                t = trim(value)
                if t in ("auto", "auto-start-reverse"):
                    rec.orient = 1 if t == "auto" else 2
                else:
                    rec.orient = 0
                    v, _ = number(t, 0)
                    rec.angle = v * 0.017453292519943295 if v is not None else 0.0
            elif name == "viewBox":
                vals, i = [], 0
                while len(vals) < 4:
                    v, i = number(value, i)
                    if v is None:
                        break
                    vals.append(v)
                if len(vals) == 4:
                    vb = vals if vals[2] > 0 and vals[3] > 0 else None
        vals = []
        for i, v in enumerate(raw):
            val, _ = length(v, "x" if i % 2 == 0 else "y", st)
            vals.append(val if val is not None else 0.0)
        rec.ref, rec.size = vals[:2], vals[2:]
        if vb and rec.size[0] > 0 and rec.size[1] > 0:
            rec.vbm = fit(vb, rec.size[0], rec.size[1], mpar)
            rec.ref = [rec.vbm[0] * rec.ref[0] + rec.vbm[4], rec.vbm[3] * rec.ref[1] + rec.vbm[5]]

    def markers(tag, st, path, uses):
        """svg_markers: marker items at the path's vertices."""
        recs = []
        for k in ("m0", "m1", "m2"):
            v = st[k]
            r = url_ref(v) if v else None
            recs.append(compile_ref(r[0], "marker", st, uses) if r else None)
        vs = vertices(path)
        if not vs:
            return
        order = [(0, recs[0], True)] + [(i, recs[1], False) for i in range(1, len(vs) - 1)] + \
            [(len(vs) - 1, recs[2], False)]
        for i, rec, is_start in order:
            if rec is None or not rec.items or not (rec.size[0] > 0 and rec.size[1] > 0):
                continue
            v = vs[i]
            a = marker_angle(v)
            if rec.orient == 0:
                a = rec.angle
            elif rec.orient == 2 and is_start:
                a = a + math.pi
            c, s = math.cos(a), math.sin(a)
            k = st["sw"] if rec.units == 0 else 1.0
            m = mul(st["m"], [1.0, 0.0, 0.0, 1.0, v[0], v[1]])
            m = mul(m, [c, s, 0.0 - s, c, 0.0, 0.0])
            m = mul(m, [k, 0.0, 0.0, k, 0.0, 0.0])
            m = mul(m, [1.0, 0.0, 0.0, 1.0, 0.0 - rec.ref[0], 0.0 - rec.ref[1]])
            doc.items.append(MarkerItem(m, rec))

    def clip_ref(raw, st, uses):
        return ref(raw, "clip-path", "clip", st, uses)

    def mask_ref(raw, st, uses):
        return ref(raw, "mask", "mask", st, uses)

    def filter_ref(raw, st):
        v = raw.get("filter")
        if clipmode[0] or v is None:
            return None
        t = trim(v)
        if t == "none" or t[:4].lower() != "url(":
            return None
        r = url_ref(t)
        el = ids.get(r[0]) if r else None
        if el is None or el.tag.split('}')[-1] != "filter":
            return None
        return filter_compile(el, st, image_fn)

    def compile_ref(cid, kind, st, uses):
        el = ids.get(cid)
        want = {"clip": "clipPath", "mask": "mask", "pattern": "pattern", "marker": "marker"}[kind]
        if compiling[0] >= MAX_CLIPS or el is None or el.tag.split('}')[-1] != want:
            return None
        compiling[0] += 1
        base = dict(default, vw=st["vw"], vh=st["vh"], font=st["font"])
        saved, doc.items = doc.items, []
        saved_mode, clipmode[0] = clipmode[0], int(kind == "clip")
        walk(el, base, uses, kind)
        clipmode[0] = saved_mode
        rec = {"clip": Clip, "mask": Mask, "pattern": Pattern, "marker": Marker}[kind](doc.items)
        doc.items = saved
        if kind == "pattern":
            pattern_attrs(rec, el, st, uses)
        elif kind == "marker":
            marker_attrs(rec, el, st)
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
        elif name in ("marker-start", "marker-mid", "marker-end", "marker"):
            t = trim(value)
            if t == "none":
                v = None
            elif t[:4].lower() == "url(":
                v = t
            else:
                return
            for k in INHERITS[name]:
                st[k] = v
        elif name in ("dominant-baseline", "alignment-baseline"):
            t = trim(value)
            if t in BASELINES:
                st["dbase"] = BASELINES[t]
        elif name == "text-decoration":
            decor = list(st["decor"])
            for w in re.split(r"[\x00- ]+", trim(value)):
                if w in ("underline", "overline", "line-through"):
                    decor[("underline", "overline", "line-through").index(w)] = st
            st["decor"] = tuple(decor)
        elif name == "font-family":
            st["family"] = trim(value)
        elif name == "font-weight":
            t, w = trim(value), st["weight"]
            if t == "normal":
                st["weight"] = 400
            elif t == "bold":
                st["weight"] = 700
            elif t == "bolder":
                st["weight"] = 400 if w < 400 else 700 if w < 600 else 900
            elif t == "lighter":
                st["weight"] = 100 if w < 600 else 400 if w < 800 else 700
            else:
                v, _ = number(t, 0)
                if v is not None and 1.0 <= v <= 1000.0:
                    st["weight"] = int(v)
        elif name == "font-style":
            t = trim(value)
            if t in ("normal", "italic", "oblique"):
                st["fstyle"] = ("normal", "italic", "oblique").index(t)
        elif name == "text-anchor":
            t = trim(value)
            if t in ("start", "middle", "end"):
                st["anchor"] = ("start", "middle", "end").index(t)
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
        if st["intext"]:
            st["intext"] = 1
        symroot = tag == "symbol" and isinstance(inst, tuple)
        cliproot = (tag == "clipPath" and inst == "clip") or (tag == "mask" and inst == "mask") or \
            (tag == "pattern" and inst == "pattern") or (tag == "marker" and inst == "marker")
        if (takes_part(tag) or symroot or cliproot) and not conditions(el):
            return
        if tag in SKIP and not (symroot or cliproot) and tag != "text":
            st["skip"] = True
        if tag == "textPath" and (not st["intext"] or st["tpath"]):
            st["skip"] = True
        if tag == "textPath" and not st["skip"]:
            st["tpath"] = 2
        elif st["tpath"]:
            st["tpath"] = 1
        if (tag == "text" and st["intext"]) or (tag == "tspan" and not st["intext"]) or \
                (tag == "text" and font_fn is None and False):
            st["skip"] = True
        if not st["skip"]:
            own = [1.0, {}]
            geom, style, el_id, classes, href, href_raw = {}, None, None, [], None, None
            lists_raw = {}
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
                    href_raw = v
                    if v.startswith('#'):
                        href = v[1:]
                elif name == "transform":
                    m = transform_list(value, st["m"])
                    if m is not None:
                        st["m"] = m
                elif name in PROPS:
                    prop(st, name, value, own, parent)
                elif name in ("dx", "dy", "rotate"):
                    lists_raw[name] = value
                elif name == "space":
                    st["preserve"] = int(trim(value) == "preserve")
                elif name in ("d", "points", "viewBox", "preserveAspectRatio"):
                    geom[name] = value
                elif name in GEOM:
                    own[1]["geom:" + name] = value
            for decls in [r[2] for r in rules if css_match(r[1], len(r[1]), el, tree)] + ([style] if style else []):
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
            for key, field_ in (("letter-spacing", "lspace"), ("word-spacing", "wspace")):
                if key in raw:
                    t = raw[key]
                    if trim(t) == "normal":
                        st[field_] = 0.0
                    else:
                        v, _ = length(t, "x", st)
                        if v is not None:
                            st[field_] = v
            if "baseline-shift" in raw and st["intext"] == 1:
                t = trim(raw["baseline-shift"])
                v = None
                if t == "baseline":
                    v = 0.0
                elif t == "sub":
                    v = st["font"] * -0.2
                elif t == "super":
                    v = st["font"] * 0.4
                else:
                    n, j = number(t, 0)
                    if n is not None and j < len(t) and t[j] == '%':
                        v = n * 0.01 * st["font"]
                    else:
                        v, _ = length(t, "y", st)
                if v is not None:
                    st["bshift"] = st["bshift"] + v
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
                    frec = filter_ref(raw, st)
                    if rec or mrec or frec or own[0] < 1.0:
                        opened = Group("begin", int(own[0] * 255.0 + 0.5), rec, list(st["m"]), mask=mrec,
                                       filter=frec)
                        doc.items.append(opened)
                        opened_at = len(doc.items)
                if symroot:
                    vp = symbol_map(st, geom, inst)
                if tag == "text":
                    st["intext"] = 2
                    st["bshift"] = 0.0
                    tx.update(x=0.0, y=0.0, count=0, space=0, any=0, chunk=0, cx=0.0, anchor=0, m=list(st["m"]),
                              onpath=None, chunkpath=None, recs=[], y0=0.0)
                    text_lists(st, el, lists_raw)
                elif tag == "tspan":
                    text_lists(st, el, lists_raw)
                elif tag == "textPath":
                    textpath_start(st, href, el)
                elif tag == "image":
                    image(geom, st, href_raw)
                elif tag == "use":
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
        intext = st["intext"] and not st["skip"]
        if intext and el.text:
            text_node(el.text, st, uses)
        for child in el:
            if tag == "switch":
                ctag = child.tag.split('}')[-1]
                if takes_part(ctag):
                    if chosen or not conditions(child):
                        continue
                    chosen = True
            walk(child, st, uses)
            if intext and child.tail:
                text_node(child.tail, st, uses)
        if st["tpath"] == 2 and not st["skip"]:
            textpath_end()
        if st["intext"] == 2 and not st["skip"]:
            text_finish()
        if vp:
            vp[0].bbox = group_bbox(vp[0], doc.items[vp[1]:])
            doc.items.append(Group("end", 255, vp[0].clip, begin=vp[0]))
        if opened:
            if opened.clip or opened.mask or opened.filter:
                opened.bbox = group_bbox(opened, doc.items[opened_at:])
            doc.items.append(Group("end", opened.alpha, opened.clip, mask=opened.mask, begin=opened,
                                   filter=opened.filter))

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
        marked = tag in MARKED and not clipmode[0] and (st["m0"] or st["m1"] or st["m2"])
        if not (fill or stroke or marked):
            return
        rec = clip_ref(raw, st, uses)
        mrec = mask_ref(raw, st, uses)
        frec = filter_ref(raw, st)
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
        if group or rec or mrec or frec:
            begin = Group("begin", int(own * 255.0 + 0.5) if group else 255, rec, list(st["m"]), mask=mrec,
                          filter=frec)
            if rec or mrec or frec:
                begin.bbox = group_bbox(begin, [item])
            doc.items += [begin, item]
            if marked:
                markers(tag, st, path, uses)
            doc.items.append(Group("end", begin.alpha, rec, mask=mrec, begin=begin, filter=frec))
        else:
            doc.items.append(item)
            if marked:
                markers(tag, st, path, uses)

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
        elif tag == "decor":
            x, y, w, h = g["rect"]
            path = [('rect', x, y, w, h)] if w > 0 and h > 0 else []
        elif tag == "glyph":
            path = g["glyph"]
        else:
            path = path_data(g.get("d", ""))
        return path

    walk(root, default)
    return doc

#!/usr/bin/env python3
"""A model of src/font/sfnt.asm and src/font/fontset.asm for checking SVG text.

    fonts = FontSet(directory)     the shipped fonts found there (fontset_standard)
    fonts.font_fn                  ugfx's font callback as fontset_svg_font answers it,
                                   in svgmodel's form: font_fn((family, weight, style),
                                   code point, size, outline) -> (advance, path) or,
                                   for code point -1, (ascent, descent)

Glyphs come from fontTools reading the same files; the outlines are turned
into path commands with the same arithmetic (composite transforms through
svgmodel.mul, points x s and 0 - y s, implied on-curve points halfway).

Development-machine tooling only; not part of any OS image.
"""
import os
import sys

from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "ugfx", "tools"))
import svgmodel  # noqa: E402

STANDARD = [
    ("NotoSans-Regular.ttf", "Noto Sans", 400, 0), ("NotoSans-Bold.ttf", "Noto Sans", 700, 0),
    ("NotoSans-Italic.ttf", "Noto Sans", 400, 1), ("NotoSans-BoldItalic.ttf", "Noto Sans", 700, 1),
    ("NotoSerif-Regular.ttf", "Noto Serif", 400, 0), ("NotoSerif-Bold.ttf", "Noto Serif", 700, 0),
    ("NotoSerif-Italic.ttf", "Noto Serif", 400, 1), ("NotoSerif-BoldItalic.ttf", "Noto Serif", 700, 1),
    ("NotoSansMono-Regular.ttf", "Noto Sans Mono", 400, 0), ("NotoSansMono-Bold.ttf", "Noto Sans Mono", 700, 0),
    ("LiberationSans-Regular.ttf", "Liberation Sans", 400, 0),
    ("LiberationSans-Bold.ttf", "Liberation Sans", 700, 0),
    ("LiberationSans-Italic.ttf", "Liberation Sans", 400, 1),
    ("LiberationSans-BoldItalic.ttf", "Liberation Sans", 700, 1),
    ("LiberationSerif-Regular.ttf", "Liberation Serif", 400, 0),
    ("LiberationSerif-Bold.ttf", "Liberation Serif", 700, 0),
    ("LiberationSerif-Italic.ttf", "Liberation Serif", 400, 1),
    ("LiberationSerif-BoldItalic.ttf", "Liberation Serif", 700, 1),
    ("LiberationMono-Regular.ttf", "Liberation Mono", 400, 0),
    ("LiberationMono-Bold.ttf", "Liberation Mono", 700, 0),
    ("LiberationMono-Italic.ttf", "Liberation Mono", 400, 1),
    ("LiberationMono-BoldItalic.ttf", "Liberation Mono", 700, 1),
]
ALIASES = {"sans-serif": "Noto Sans", "system-ui": "Noto Sans", "ui-sans-serif": "Noto Sans",
           "cursive": "Noto Sans", "fantasy": "Noto Sans", "serif": "Noto Serif", "ui-serif": "Noto Serif",
           "monospace": "Noto Sans Mono", "ui-monospace": "Noto Sans Mono", "arial": "Liberation Sans",
           "helvetica": "Liberation Sans", "helvetica neue": "Liberation Sans", "arimo": "Liberation Sans",
           "times new roman": "Liberation Serif", "times": "Liberation Serif", "tinos": "Liberation Serif",
           "courier new": "Liberation Mono", "courier": "Liberation Mono", "cousine": "Liberation Mono"}


class Face:
    def __init__(self, path, family, weight, italic):
        self.family, self.weight, self.italic = family, weight, italic
        self.font = TTFont(path)
        self.upem = self.font["head"].unitsPerEm
        hhea = self.font["hhea"]
        self.asc, self.desc = hhea.ascent, -hhea.descent
        self.order = self.font.getGlyphOrder()
        cmap = None
        for t in self.font["cmap"].tables:          # format 12 Unicode over format 4, first of each
            uni = t.platformID == 0 or (t.platformID == 3 and t.platEncID in (1, 10))
            if uni and t.format == 12 and (cmap is None or cmap.format != 12):
                cmap = t
            elif uni and t.format == 4 and cmap is None:
                cmap = t
        self.cmap = cmap.cmap

    def glyph(self, cp):
        name = self.cmap.get(cp) if cp >= 0 else None
        return 0 if name is None else self.font.getGlyphID(name)

    def advance(self, gid):
        return self.font["hmtx"][self.order[gid]][0]

    def outline(self, gid, s):
        out = []
        self._emit(gid, [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], s, out, 0)
        return out

    def _emit(self, gid, m, s, out, depth):
        g = self.font["glyf"][self.order[gid]]
        if g.isComposite():
            for c in g.components:
                dx, dy = (float(c.x), float(c.y)) if hasattr(c, "x") else (0.0, 0.0)
                a, b, cc, d = 1.0, 0.0, 0.0, 1.0
                if hasattr(c, "transform"):
                    (a, b), (cc, d) = c.transform
                if c.flags & 0x800:
                    dx, dy = a * dx + cc * dy, b * dx + d * dy
                self._emit(self.order.index(c.glyphName), svgmodel.mul(m, [a, b, cc, d, dx, dy]), s, out,
                           depth + 1)
            return
        if not hasattr(g, "coordinates") or g.numberOfContours <= 0:
            return
        pts, flags = g.coordinates, g.flags

        def point(i):
            x, y = float(pts[i][0]), float(pts[i][1])
            return m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]

        def px(p):
            return p[0] * s, 0.0 - p[1] * s

        first = 0
        for end in g.endPtsOfContours:
            n = end + 1 - first
            idx = list(range(first, end + 1))
            first = end + 1
            if n == 0:
                continue
            on = [flags[i] & 1 for i in idx]
            if on[0]:
                start, seq = point(idx[0]), idx[1:]
            elif on[-1]:
                start, seq = point(idx[-1]), idx[:-1]
            else:
                p0, p1 = point(idx[0]), point(idx[-1])
                start, seq = ((p1[0] + p0[0]) * 0.5, (p1[1] + p0[1]) * 0.5), idx
            out.append(('move', *px(start)))
            ctrl = None
            for i in seq:
                p = point(i)
                if flags[i] & 1:
                    if ctrl is not None:
                        out.append(('quad', *px(ctrl), *px(p)))
                        ctrl = None
                    else:
                        out.append(('line', *px(p)))
                elif ctrl is not None:
                    mid = ((p[0] + ctrl[0]) * 0.5, (p[1] + ctrl[1]) * 0.5)
                    out.append(('quad', *px(ctrl), *px(mid)))
                    ctrl = p
                else:
                    ctrl = p
            if ctrl is not None:
                out.append(('quad', *px(ctrl), *px(start)))
            out.append(('close',))


class FontSet:
    def __init__(self, directory):
        self.faces = [Face(os.path.join(directory, f), fam, w, it) for f, fam, w, it in STANDARD
                      if os.path.exists(os.path.join(directory, f))]

    def family(self, name, want):
        best, score = None, -1
        for f in self.faces:
            if f.family.lower() != name.lower():
                continue
            have = (f.weight >= 600) | (f.italic << 1)
            diff = have ^ want
            sc = (0 if diff & 2 else 2) + (0 if diff & 1 else 1)
            if sc > score:
                best, score = f, sc
        return best

    def face(self, family, weight, style):
        want = (weight >= 600) | ((style != 0) << 1)
        for item in (family.split(',') if family is not None else []):
            name = item.strip("".join(chr(c) for c in range(33)))
            if len(name) >= 2 and name[0] in "\"'" and name[-1] == name[0]:
                name = name[1:-1]
            if not name:
                continue
            name = ALIASES.get(name.lower(), name)
            f = self.family(name, want)
            if f is not None:
                return f
        f = self.family("Noto Sans", want)
        if f is None and self.faces:
            f = self.faces[0]
        return f

    def font_fn(self, font, cp, size, outline):
        family, weight, style = font
        face = self.face(family, weight, style)
        if face is None:
            return (0.0, 0.0) if cp == -1 else (0.0, [])
        s = size / face.upem
        if cp == -1:
            return face.asc * s, face.desc * s
        gid = face.glyph(cp)
        if gid == 0:
            want = (weight >= 600) | ((style != 0) << 1)
            fb = self.family("Noto Sans", want)
            if fb is not None and fb is not face:
                g2 = fb.glyph(cp)
                if g2:
                    face, gid, s = fb, g2, size / fb.upem
        adv = face.advance(gid) * s
        return adv, (face.outline(gid, s) if outline else [])


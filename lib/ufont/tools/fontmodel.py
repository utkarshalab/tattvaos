#!/usr/bin/env python3
"""A model of lib/ufont (sfnt/sfnt.asm, match/fontset.asm) for checking it and SVG text.

    fonts = FontSet(directory)     the shipped fonts found there (ufont_standard)
    face = fonts.face(family, weight, style)   the face ufont_set_face picks; face.std is
                                   its index in ufont_standard
    face.glyph(cp), face.advance(gid), face.outline(gid, scale)
                                   ufont_glyph / ufont_advance / ufont_outline
    fonts.font_fn                  ugfx's font callback as ufont_svg_font answers it,
                                   in svgmodel's form: font_fn((family, weight, style),
                                   code point, size, outline) -> (advance, path) or,
                                   for code point -1, (ascent, descent); a code point
                                   with bit 31 set is a glyph key from shape_fn
    fonts.shape_fn                 ugfx's shaping callback as ufont_svg_shape answers it:
                                   shape_fn((family, weight, style), code points, size)
                                   -> [(glyph key, cluster, advance, x offset, y offset
                                   down)] - runs split by face and script, each shaped by
                                   tools/shapemodel.py

A character the face lacks comes from Noto Sans in the style, else from the
first face in the set that has it (same weight and style, then same weight,
then any); marks and default ignorables stay in the face before them.

Glyphs come from fontTools reading the same files; the outlines are turned
into path commands with the same arithmetic (composite transforms through
svgmodel.mul, points x s and 0 - y s, implied on-curve points halfway).

Development-machine tooling only; not part of any OS image.
"""
import os
import sys

from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "ugfx", "tools"))
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
    ("NotoSansDevanagari-Regular.ttf", "Noto Sans Devanagari", 400, 0),
    ("NotoSansDevanagari-Bold.ttf", "Noto Sans Devanagari", 700, 0),
    ("NotoSerifDevanagari-Regular.ttf", "Noto Serif Devanagari", 400, 0),
    ("NotoSerifDevanagari-Bold.ttf", "Noto Serif Devanagari", 700, 0),
    ("NotoSansBengali-Regular.ttf", "Noto Sans Bengali", 400, 0),
    ("NotoSansBengali-Bold.ttf", "Noto Sans Bengali", 700, 0),
    ("NotoSansGurmukhi-Regular.ttf", "Noto Sans Gurmukhi", 400, 0),
    ("NotoSansGurmukhi-Bold.ttf", "Noto Sans Gurmukhi", 700, 0),
    ("NotoSansGujarati-Regular.ttf", "Noto Sans Gujarati", 400, 0),
    ("NotoSansGujarati-Bold.ttf", "Noto Sans Gujarati", 700, 0),
    ("NotoSansOriya-Regular.ttf", "Noto Sans Oriya", 400, 0),
    ("NotoSansOriya-Bold.ttf", "Noto Sans Oriya", 700, 0),
    ("NotoSansTamil-Regular.ttf", "Noto Sans Tamil", 400, 0),
    ("NotoSansTamil-Bold.ttf", "Noto Sans Tamil", 700, 0),
    ("NotoSansTelugu-Regular.ttf", "Noto Sans Telugu", 400, 0),
    ("NotoSansTelugu-Bold.ttf", "Noto Sans Telugu", 700, 0),
    ("NotoSansKannada-Regular.ttf", "Noto Sans Kannada", 400, 0),
    ("NotoSansKannada-Bold.ttf", "Noto Sans Kannada", 700, 0),
    ("NotoSansMalayalam-Regular.ttf", "Noto Sans Malayalam", 400, 0),
    ("NotoSansMalayalam-Bold.ttf", "Noto Sans Malayalam", 700, 0),
    ("NotoSansArabic-Regular.ttf", "Noto Sans Arabic", 400, 0),
    ("NotoSansArabic-Bold.ttf", "Noto Sans Arabic", 700, 0),
    ("NotoNaskhArabic-Regular.ttf", "Noto Naskh Arabic", 400, 0),
    ("NotoNaskhArabic-Bold.ttf", "Noto Naskh Arabic", 700, 0),
    ("NotoSansHebrew-Regular.ttf", "Noto Sans Hebrew", 400, 0),
    ("NotoSansHebrew-Bold.ttf", "Noto Sans Hebrew", 700, 0),
    ("NotoSerifHebrew-Regular.ttf", "Noto Serif Hebrew", 400, 0),
    ("NotoSerifHebrew-Bold.ttf", "Noto Serif Hebrew", 700, 0),
]
ALIASES = {"sans-serif": "Noto Sans", "system-ui": "Noto Sans", "ui-sans-serif": "Noto Sans",
           "cursive": "Noto Sans", "fantasy": "Noto Sans", "serif": "Noto Serif", "ui-serif": "Noto Serif",
           "monospace": "Noto Sans Mono", "ui-monospace": "Noto Sans Mono", "arial": "Liberation Sans",
           "helvetica": "Liberation Sans", "helvetica neue": "Liberation Sans", "arimo": "Liberation Sans",
           "times new roman": "Liberation Serif", "times": "Liberation Serif", "tinos": "Liberation Serif",
           "courier new": "Liberation Mono", "courier": "Liberation Mono", "cousine": "Liberation Mono"}


class Face:
    def __init__(self, path, family, weight, italic, std=-1):
        self.family, self.weight, self.italic, self.std = family, weight, italic, std
        self.path = path
        self._shaper = None
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

    def shaper(self):
        if self._shaper is None:
            import shapemodel
            self._shaper = shapemodel.Font(self.path)
        return self._shaper

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
        self.faces = [Face(os.path.join(directory, f), fam, w, it, i) for i, (f, fam, w, it) in enumerate(STANDARD)
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

    def char_face(self, face, cp, want):
        """The face a character is drawn from: the face, else Noto Sans in the style, else the
        first face with it (same weight and style, then same weight, then any)."""
        if face.glyph(cp):
            return face
        fb = self.family("Noto Sans", want)
        if fb is not None and fb is not face and fb.glyph(cp):
            return fb
        for match in (3, 1, 0):
            for f in self.faces:
                have = (f.weight >= 600) | (f.italic << 1)
                if (have & match) == (want & match) and f.glyph(cp):
                    return f
        return face

    def font_fn(self, font, cp, size, outline):
        family, weight, style = font
        face = self.face(family, weight, style)
        if face is None:
            return (0.0, 0.0) if cp == -1 else (0.0, [])
        if cp == -1:
            s = size / face.upem
            return face.asc * s, face.desc * s
        if cp >= 0x80000000:
            k = (cp >> 16) & 0x7FFF
            if k < len(self.faces):
                face = self.faces[k]
            gid = cp & 0xFFFF
        else:
            face = self.char_face(face, cp, (weight >= 600) | ((style != 0) << 1))
            gid = face.glyph(cp)
        s = size / face.upem
        adv = face.advance(gid) * s
        return adv, (face.outline(gid, s) if outline else [])

    def shape_fn(self, font, cps, size):
        import shapemodel as sm
        from fontTools import unicodedata as fud
        family, weight, style = font
        primary = self.face(family, weight, style)
        if primary is None:
            return None
        want = (weight >= 600) | ((style != 0) << 1)
        faces = []
        for i, cp in enumerate(cps):
            if i and (sm.is_mark_gc(sm.gc(cp)) or sm.is_default_ignorable(cp)):
                faces.append(faces[-1])
            else:
                faces.append(self.char_face(primary, cp, want))
        strong = [fud.script(chr(cp)) for cp in cps]
        strong = [None if sc in ('Zyyy', 'Zinh', 'Zzzz') else sc for sc in strong]
        first = next((sc for sc in strong if sc is not None), None)
        scripts, last = [], first
        for sc in strong:
            last = sc if sc is not None else last
            scripts.append(last)
        out, a = [], 0
        while a < len(cps):
            b = a + 1
            while b < len(cps) and faces[b] is faces[a] and scripts[b] == scripts[a]:
                b += 1
            face = faces[a]
            s = size / face.upem
            k = self.faces.index(face)
            for g, cl, xa, ya, xo, yo in sm.shape(face.shaper(), cps[a:b], script=scripts[a]):
                out.append((0x80000000 | (k << 16) | g, a + cl, xa * s, xo * s, 0.0 - yo * s))
            a = b
        return out

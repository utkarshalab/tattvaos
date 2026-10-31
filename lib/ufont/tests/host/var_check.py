#!/usr/bin/env python3
"""Check lib/ufont's variable fonts.

Usage: var_check.py <host_font> <host_shape> <test font directory>

For the variable test fonts (tests/fonts/*-VF-test.ttf) at several axis
settings - the corners, the default, points between, out of range:
every glyph's outline (ufont_set_variations, then ufont_outline at two
sizes, the second from the cache) equal to tools/fontmodel.py's (gvar,
IUP, composites, phantom points), and the model's equal to HarfBuzz's
drawing within 0.01 units (HarfBuzz varies in float32); shaping (HVAR
advances, GPOS variation devices, anchors) equal to tools/shapemodel.py
and the model to HarfBuzz; a font with GSUB feature variations made from
one of them (wght and wdth conditions switching substitutions) shaped
across the axes. Damaged variable fonts never crash the tools.

Development-machine tooling only; not part of any OS image.
"""
import glob
import os
import struct
import random
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.join(HERE, "..", "..", "tools")]
import fontmodel  # noqa: E402
import font_check  # noqa: E402
import shape_check  # noqa: E402
import shapemodel as sm  # noqa: E402
import var_fonts  # noqa: E402

try:
    import uharfbuzz as hb
except ImportError:
    hb = None

SETTINGS = [{"wght": 700}, {"wght": 100, "wdth": 62.5}, {"wght": 900, "wdth": 75}, {"wght": 523.7, "wdth": 91.3},
            {"wght": 400}, {"wght": 2000, "wdth": 10}, {"wdth": 87.5}]


class Pen:
    def __init__(self):
        self.out, self.start = [], None

    def moveTo(self, p):
        self.start = p
        self.out.append(("move", p[0], p[1]))

    def lineTo(self, p):
        self.out.append(("line", p[0], p[1]))

    def qCurveTo(self, a, b):
        self.out.append(("quad", a[0], a[1], b[0], b[1]))

    def curveTo(self, a, b, c):
        self.out.append(("cubic", *a, *b, *c))

    def closePath(self):
        # HarfBuzz lines back to the start first; ufont's close does that
        if self.out and self.out[-1][0] == "line" and self.out[-1][1:] == tuple(self.start):
            self.out.pop()
        self.out.append(("close",))

    endPath = closePath


def model_vs_harfbuzz(path, face, settings):
    hfont = hb.Font(hb.Face(hb.Blob.from_file_path(path)))
    hfont.set_variations(settings)
    bad = 0
    for gid in range(len(face.order)):
        pen = Pen()
        hfont.draw_glyph_with_pen(gid, pen)
        got = [(c[0],) + tuple(v if k % 2 == 0 else -v for k, v in enumerate(c[1:])) for c in face.outline(gid, 1.0)]
        ok = len(got) == len(pen.out) and all(
            a[0] == b[0] and len(a) == len(b) and all(abs(x - y) <= 0.01 for x, y in zip(a[1:], b[1:]))
            for a, b in zip(got, pen.out))
        bad += not ok
    return bad


def main():
    font_tool, shape_tool = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    font_dir = os.path.abspath(sys.argv[3])
    rng = random.Random(8)
    failed = total = 0
    paths = sorted(glob.glob(os.path.join(font_dir, "*-VF-test.ttf")))
    with tempfile.TemporaryDirectory(prefix="ufont-var.") as d:
        fv = os.path.join(d, "NotoSans-featvar.ttf")
        var_fonts.make_featvar(os.path.join(font_dir, "NotoSans-VF-test.ttf"), fv)
        for path in paths:
            name = os.path.basename(path)
            for s in SETTINGS:
                face = fontmodel.Face(path, "Test VF", 400, 0)
                face.settings = s
                face.set_variations(s)
                err = font_check.check_glyphs(font_tool, d, path, face)
                note = ""
                if hb is not None:
                    note = f"  model vs HarfBuzz: {len(face.order) - model_vs_harfbuzz(path, face, s)}/{len(face.order)}"
                total += 1
                failed += err is not None
                print(f"{'ok  ' if err is None else 'FAIL'}  outlines {name:32} {str(s):34}{note}"
                      + (f"  {err}" if err else ""))
        for path in paths + [fv]:
            name = os.path.basename(path)
            font = sm.Font(path)
            cmap = sorted(font.cmap)
            marks = [c for c in cmap if sm.is_mark_gc(sm.gc(c))]
            for k in range(6):
                s = SETTINGS[k] if k < 4 else {"wght": rng.uniform(90, 910), "wdth": rng.uniform(60, 101)}
                shape_check.VARIATIONS = s
                cases = [[ord(c) for c in w] for w in shape_check.WORDS[:80]]
                for _ in range(120):
                    if "Arabic" in name:
                        cases.append(shape_check.rtl_text(rng, True))
                    elif "Devanagari" in name:
                        cases.append(shape_check.devanagari(rng))
                    else:
                        cases.append(shape_check.general(rng, cmap, marks))
                total += 1
                failed += not shape_check.check_font(shape_tool, path, f"{name} {s}", cases, d)
        shape_check.VARIATIONS = {}
        # damaged
        crashes = runs = 0
        data = open(paths[0], "rb").read()
        src = os.path.join(d, "in.bin")
        open(src, "wb").write(struct.pack("<I4sfddI", 1, b"wght", 750.0, 20.0, 11.0, 3) + struct.pack("<3I", 0x61, 0xC5, 0x31))
        for _ in range(120):
            b = bytearray(data)
            for _ in range(rng.choice((1, 4, 32))):
                b[rng.randrange(len(b))] = rng.randrange(256)
            p = os.path.join(d, "damaged.ttf")
            open(p, "wb").write(bytes(b))
            rc = font_check.run(font_tool, "o", p, src, os.path.join(d, "out.bin"))
            runs += 1
            crashes += rc not in (0, 2)
        total += 1
        failed += crashes > 0
        print(f"{'ok  ' if not crashes else 'FAIL'}  damaged variable fonts {runs} runs, {crashes} crashed")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check SVG text in Canvas: lib/ufont's fonts through its sfnt reader and font sets.

Usage: svg_text_check.py <host_decode> <ugfx host_ctx> <font directory>

Every lib/ugfx svg_check.py document with text, and the documents below
(families, generic names and aliases, weights and styles, Latin accents
from composite glyphs, Greek, Cyrillic, characters a face lacks, sizes,
transforms, decorations, textPath), is decoded by Canvas with the fonts
(host_decode ... <font directory>) and compared with the context calls
svgmodel derives using lib/ufont's fontmodel.FontSet - the same glyphs and
arithmetic - drawn by ugfx's host_ctx. The images must be identical. Damaged fonts
(truncated, bytes changed) must never crash the decoder.

Development-machine tooling only; not part of any OS image.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
UGFX = os.path.join(HERE, "..", "..", "..", "ugfx")
UFONT = os.path.join(HERE, "..", "..", "..", "ufont")
sys.path[:0] = [HERE, os.path.join(UFONT, "tools"), os.path.join(UGFX, "tests", "host"), os.path.join(UGFX, "tools")]
import fontmodel  # noqa: E402
import ctx_check  # noqa: E402
import svgmodel  # noqa: E402
from svg_check import CASES, expected_calls, farbfeld  # noqa: E402
from svg_decode_check import decode, own_size  # noqa: E402


def svg(body, attrs='viewBox="0 0 240 120"'):
    return f'<svg xmlns="http://www.w3.org/2000/svg" {attrs}>{body}</svg>'


DOCS = [
    ("families", svg('<text x="4" y="18" font-size="15">Default: Noto Sans Ag</text>'
                     '<text x="4" y="38" font-size="15" font-family="serif">Serif Ag</text>'
                     '<text x="120" y="38" font-size="15" font-family="monospace">Mono Ag</text>'
                     '<text x="4" y="58" font-size="15" font-family="Arial, sans-serif">Arial</text>'
                     '<text x="80" y="58" font-size="15" font-family="\'Times New Roman\'">Times</text>'
                     '<text x="160" y="58" font-size="15" font-family=\'"Courier New"\'>Courier</text>'
                     '<text x="4" y="78" font-size="15" font-family="Nonesuch, Cousine">Cousine</text>'
                     '<text x="100" y="78" font-size="15" font-family="nonesuch">fallback</text>'
                     '<text x="4" y="98" font-size="15" font-family="  NOTO serif ">case</text>'
                     '<text x="80" y="98" font-size="15" style="font-family: Liberation Sans">LibSans</text>'
                     '<text x="170" y="98" font-size="15" font-family="cursive">curs</text>')),
    ("weights styles", svg('<text x="4" y="18" font-size="14">Regular <tspan font-weight="bold">Bold</tspan> '
                           '<tspan font-style="italic">Italic</tspan> <tspan font-weight="800" '
                           'font-style="oblique">BoldIt</tspan></text>'
                           '<text x="4" y="40" font-size="14" font-family="serif" font-weight="600">Semi '
                           '<tspan font-weight="lighter">lighter</tspan> <tspan font-style="italic" '
                           'font-weight="300">light italic</tspan></text>'
                           '<text x="4" y="62" font-size="14" font-family="monospace" font-style="italic">'
                           'mono italic <tspan font-weight="bold">bold</tspan></text>'
                           '<text x="4" y="84" font-size="14" font-family="Times" font-weight="900" '
                           'font-style="italic">Times black italic</text>'
                           '<text x="4" y="106" font-size="14" font-family="Courier" '
                           'font-weight="bold">Courier bold</text>')),
    ("scripts", svg('<text x="4" y="20" font-size="16">Åsa Øre çà ñ ŝ ẞ ŉ ǅ ﬁ</text>'
                    '<text x="4" y="44" font-size="16" font-family="serif">Ζεύς ἀρχή Москва Ўў Ґґ</text>'
                    '<text x="4" y="68" font-size="16" font-family="Arial">€ £ ¥ № ™ ← ↔ ∑ √ ∞ ≠</text>'
                    '<text x="4" y="92" font-size="16" font-family="Times">“quotes” – — … • ‰</text>'
                    '<text x="4" y="114" font-size="16">✓ 漢 ❤ missing</text>')),
    ("sizes transforms", svg('<text x="4" y="10" font-size="6">tiny six</text>'
                             '<text x="4" y="60" font-size="48" font-family="serif">Big</text>'
                             '<g transform="translate(130 20) rotate(20) scale(1.5 .8)"><text font-size="14" '
                             'fill="#a30" stroke="#036" stroke-width=".6">Turned</text></g>'
                             '<text x="4" y="100" font-size="16" text-decoration="underline line-through" '
                             'fill="#063" letter-spacing="2">spaced out</text>'
                             '<text x="236" y="112" font-size="12" text-anchor="end" font-family="monospace">'
                             'end anchored</text>'), True),
    ("text path", svg('<path id="c" d="M10 100 C60 10 180 10 230 100" fill="none" stroke="#ccc"/>'
                      '<text font-size="15" font-family="serif" fill="#036"><textPath href="#c" '
                      'startOffset="50%" text-anchor="middle">Along the curve, Ελλάδα</textPath></text>')),
]


def main():
    decode_tool, ctx_tool, font_dir = (os.path.abspath(p) for p in sys.argv[1:4])
    fonts = fontmodel.FontSet(font_dir)
    cases = [(n, t, trig) for n, t, trig in CASES if "<text" in t]
    cases += [(n, t, False) for n, t in [d[:2] for d in DOCS if len(d) == 2]]
    cases += [d for d in DOCS if len(d) == 3]
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="canvas_text.") as d:
        for name, text, trig in cases:
            total += 1
            got, rc = decode(decode_tool, d, text.encode(), font_dir)
            w, h = own_size(text)
            ctx_check.W, ctx_check.H, ctx_check.BG = w, h, 0
            side = float(max(w, h))
            doc = svgmodel.parse(text, farbfeld, fonts.font_fn)
            cmds = expected_calls(doc, 0xFF000000, (w - side) * 0.5, (h - side) * 0.5, side)
            sp, raw = os.path.join(d, "c.bin"), os.path.join(d, "c.raw")
            open(sp, "wb").write(ctx_check.encode(cmds))
            r = subprocess.run([ctx_tool, sp, raw], capture_output=True, timeout=120)
            if got is None or r.returncode:
                print(f"FAIL  {name:20} decode exit {rc}, ugfx exit {r.returncode}")
                failed += 1
                continue
            gw, gh, px = got
            want = np.frombuffer(open(raw, "rb").read(), np.uint8)
            if px.shape != want.shape:
                print(f"FAIL  {name:20} {gw}x{gh} (want {w}x{h})")
                failed += 1
                continue
            diff = np.abs(px.astype(int) - want.astype(int)).reshape(-1, 4).max(axis=1)
            off = int((diff > 1).sum())
            ok = (gw, gh) == (w, h) and (int(diff.max()) == 0 or (trig and off <= 3))
            painted = int((want.reshape(-1, 4)[:, 3] > 0).sum())
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:20} {gw}x{gh} items={len(doc.items):3} "
                  f"max_diff={int(diff.max()):3d} pixels_off={off} painted={painted}")
        # damaged fonts: truncated, bytes flipped (tables, glyphs, cmap) - text may be lost, never the decoder
        import random
        rng = random.Random(7)
        src = open(os.path.join(font_dir, "NotoSans-Regular.ttf"), "rb").read()
        doc = svg('<text x="4" y="40" font-size="20">Damaged Åg ffi 0123</text>').encode()
        variants = [src[:n] for n in (0, 11, 12, 100, 400, len(src) // 3, len(src) - 1)]
        for _ in range(40):
            b = bytearray(src)
            for _ in range(rng.choice((1, 4, 32))):
                i = rng.randrange(len(b)) if rng.random() < 0.5 else rng.randrange(min(len(b), 2048))
                b[i] = rng.randrange(256)
            variants.append(bytes(b))
        fd = os.path.join(d, "fonts")
        os.makedirs(fd, exist_ok=True)
        crashes = 0
        for v in variants:
            open(os.path.join(fd, "NotoSans-Regular.ttf"), "wb").write(v)
            _, rc = decode(decode_tool, d, doc, fd)
            crashes += rc not in (0, 3)
        total += 1
        failed += crashes > 0
        print(f"{'ok  ' if not crashes else 'FAIL'}  damaged fonts        {len(variants)} variants, "
              f"{crashes} crashed")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

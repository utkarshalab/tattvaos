#!/usr/bin/env python3
"""Check Canvas SVG decoding (src/img/svg.asm over lib/ugfx).

Usage: svg_decode_check.py <host_decode> <ugfx host_ctx>

Every lib/ugfx svg_check.py document is decoded by Canvas's image pipeline
(host_decode -> image_decode -> svg_render) and drawn by ugfx directly
(host_ctx: the document at its own size, transparent, currentColor
black, fitted and centred as svg_render does). The images must be
identical, and the size must be the document's (viewBox, else width /
height, else 300 x 150, rounded). Non-SVG and broken documents must fail
to decode.

Development-machine tooling only; not part of any OS image.
"""
import os
import struct
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
UGFX = os.path.join(HERE, "..", "..", "..", "ugfx")
sys.path[:0] = [os.path.join(UGFX, "tests", "host"), os.path.join(UGFX, "tools")]
import ctx_check  # noqa: E402
import svgmodel  # noqa: E402
from svg_check import CASES  # noqa: E402


def own_size(text):
    doc = svgmodel.parse(text)
    if doc.viewbox:
        w, h = doc.viewbox[2], doc.viewbox[3]
    else:
        w = doc.width if doc.width and doc.width > 0 else 300.0
        h = doc.height if doc.height and doc.height > 0 else 150.0
    w, h = int(min(w, 16384.0) + 0.5), int(min(h, 16384.0) + 0.5)
    return max(w, 1), max(h, 1)


def decode(tool, d, data):
    src, raw = os.path.join(d, "in.svg"), os.path.join(d, "out.raw")
    open(src, "wb").write(data)
    r = subprocess.run([tool, src, raw], capture_output=True, timeout=60)
    if r.returncode:
        return None, r.returncode
    b = open(raw, "rb").read()
    w, h, stride, fmt = struct.unpack_from("<4I", b)
    return (w, h, np.frombuffer(b[16:], np.uint8)), 0


def main():
    decode_tool, ctx_tool = (os.path.abspath(p) for p in sys.argv[1:3])
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="canvas_svg.") as d:
        for name, text, _ in CASES:
            if "<text" in text:
                continue                # ugfx's checks draw text with a test font; Canvas's fonts differ
            total += 1
            got, rc = decode(decode_tool, d, text.encode())
            w, h = own_size(text)
            ctx_check.W, ctx_check.H, ctx_check.BG = w, h, 0
            side = float(max(w, h))
            cmds = [('svg', text.encode(), 0xFF000000, (w - side) * 0.5, (h - side) * 0.5, side)]
            sp, raw = os.path.join(d, "c.bin"), os.path.join(d, "c.raw")
            open(sp, "wb").write(ctx_check.encode(cmds))
            r = subprocess.run([ctx_tool, sp, raw], capture_output=True, timeout=60)
            if got is None or r.returncode:
                print(f"FAIL  {name:20} decode exit {rc}, ugfx exit {r.returncode}")
                failed += 1
                continue
            gw, gh, px = got
            want = np.frombuffer(open(raw, "rb").read(), np.uint8)
            ok = (gw, gh) == (w, h) and px.shape == want.shape and bool((px == want).all())
            diff = int(np.abs(px.astype(int) - want.astype(int)).max()) if px.shape == want.shape else -1
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:20} {gw}x{gh} (want {w}x{h}) max_diff={diff}")
        for name, data in (("not svg", b"<html><body/></html>"), ("empty svg tag only", b"<svg"),
                           ("too deep", b"<svg>" + b"<g>" * 70 + b"</svg>")):
            total += 1
            got, rc = decode(decode_tool, d, data)
            ok = got is None
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  refuse {name:18} exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

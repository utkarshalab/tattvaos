#!/usr/bin/env python3
"""Check tools/svg2uic.py: a converted icon draws like the SVG it came from.

Usage: svg2uic_check.py <host_ctx binary>

Every svg_check.py document is converted and packed; ugfx draws the SVG
(ugfx_svg_draw, with the current colour) and the UIC icon (ugfx_uic_draw,
slot 0 given that colour when the icon uses currentColor) at the same
box. UIC keeps coordinates as i16 fixed point, so edges may move by a
fraction of 1/2^f units: the images must agree within MAX_DIFF per channel
everywhere and MEAN_DIFF on average.

Development-machine tooling only; not part of any OS image.
"""
import os
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import svg2uic  # noqa: E402
from ctx_check import encode  # noqa: E402
from svg_check import CASES  # noqa: E402
from uic import pack  # noqa: E402

MAX_DIFF = 2
MEAN_DIFF = 0.02


def run(tool, d, cmds):
    sp, raw = os.path.join(d, "c.bin"), os.path.join(d, "c.raw")
    open(sp, "wb").write(encode(cmds))
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    return (np.frombuffer(open(raw, "rb").read(), np.uint8).astype(int) if r.returncode == 0 else None), r.returncode


def main():
    tool = os.path.abspath(sys.argv[1])
    failed = total = 0
    worst = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_svg2uic.") as d:
        for name, text, _ in CASES:
            if "Gradient" in text or "dasharray" in text or "<pattern" in text or "<marker" in text or                     "<text" in text or "<filter" in text or \
                    any(isinstance(it, svg2uic.svgmodel.Group) for it in svg2uic.svgmodel.parse(text).items):
                continue                # UIC has no gradients, dashes or layers: svg2uic approximates them
            icon, warnings = svg2uic.convert(text, "icon")
            data = pack([icon])
            uses_current = any(p and p[0] == "current" for it in svg2uic.svgmodel.parse(text).items
                               for p in (it.fill, it.stroke))
            for current, (x, y, size) in ((0xFF2050C0, (8, 0, 32)), (0x80E0E020, (2, 3, 27.5))):
                total += 1
                want, rc = run(tool, d, [('svg', text.encode(), current, x, y, size)])
                cols = [current] if uses_current else []
                got, rc2 = run(tool, d, [('uic', data, "icon", 0, 0, x, y, size, 1.0, cols)])
                if want is None or got is None:
                    print(f"FAIL  {name:20} exit {rc}/{rc2}")
                    failed += 1
                    continue
                diff = np.abs(got - want)
                mx, mean = int(diff.max()), float(diff.mean())
                worst = max(worst, mx)
                ok = mx <= MAX_DIFF and mean <= MEAN_DIFF
                failed += not ok
                print(f"{'ok  ' if ok else 'FAIL'}  {name:20} slots={len(icon.slots):2} cmds={len(icon.commands):3} "
                      f"max_diff={mx:3d} mean={mean:.4f}" + (f"  ({len(warnings)} warnings)" if warnings else ""))
    print(f"{total - failed}/{total} passed (worst channel difference {worst})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Check Canvas's built-in UI icons and decoration buttons.

Usage: ui_icons_check.py <host_ui> <ugfx host_ctx>

Icons: every icon of assets/icons/ui.uic is drawn by canvas_icon_draw
(host_ui) and by ugfx directly (host_ctx: ugfx_uic_draw of the same pack,
size and colour); the images must be identical. An unknown name fails.

Decorations: decoration_draw_frame (host_ui) must give exactly the frame
the drawing rules describe, built here with the ugfx context: the
titlebar, the borders, each button's background (squares of titlebar - 4
pixels, right-aligned with 2-pixel gaps, 2 pixels from the top) and its
icon (x, square, minus, menu) at 3/4 of the button, centred, in the
foreground colour.

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
from uic_sheet import read_pack  # noqa: E402

PACK = open(os.path.join(HERE, "..", "..", "assets", "icons", "ui.uic"), "rb").read()
NAMES = [n for n, _, _ in read_pack(PACK)]
BUTTON_ICONS = {0: "x", 1: "square", 2: "minus", 3: "menu"}


def host_ui(tool, d, w, h, bg, cmds):
    out = struct.pack("<4IQ", w, h, bg, 0, len(cmds))
    for c in cmds:
        if c[0] == 'icon':
            _, name, colour, x, y, size, weight = c
            b = name.encode()
            out += struct.pack("<Q6d", 1, colour, x, y, size, weight, len(b)) + b + bytes(-len(b) % 8)
        else:
            _, th, bw, tc, bc, bbg, bfg, types = c
            out += struct.pack(f"<Q7d{len(types)}d", 2, th, bw, tc, bc, bbg, bfg, len(types), *types)
    sp, raw = os.path.join(d, "u.bin"), os.path.join(d, "u.raw")
    open(sp, "wb").write(out)
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    return (np.frombuffer(open(raw, "rb").read(), np.uint8) if r.returncode == 0 else None), r.returncode


def host_ctx(tool, d, w, h, bg, cmds):
    ctx_check.W, ctx_check.H, ctx_check.BG = w, h, bg
    sp, raw = os.path.join(d, "c.bin"), os.path.join(d, "c.raw")
    open(sp, "wb").write(ctx_check.encode(cmds))
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    return (np.frombuffer(open(raw, "rb").read(), np.uint8) if r.returncode == 0 else None), r.returncode


def frame_calls(w, h, th, bw, tc, bc, bbg, bfg, types):
    th = min(th, h)
    out = [('fill_color', tc), ('fill_rect', 0, 0, w, th)]
    if bw:
        out += [('fill_color', bc), ('fill_rect', 0, 0, bw, h), ('fill_rect', w - bw, 0, bw, h),
                ('fill_rect', 0, h - bw, w, bw)]
    size = max(th - 4, 4)
    for i, t in enumerate(types):
        k = len(types) - i
        x, y = w - 2 - (size + 2) * k, 2
        out += [('fill_color', bbg), ('fill_rect', x, y, size, size)]
        if t in BUTTON_ICONS:
            s = size * 0.75
            name = BUTTON_ICONS[t]
            out.append(('uic', PACK, name, int(s), NAMES.index(name), (size - s) * 0.5 + x, (size - s) * 0.5 + y,
                        s, 1.0, [bfg]))
    return out


def main():
    ui_tool, ctx_tool = (os.path.abspath(p) for p in sys.argv[1:3])
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="canvas_ui.") as d:
        for name in NAMES:
            for colour, x, y, size, weight, bg in ((0xFF202020, 4, 4, 24, 1.0, 0xFFFFFFFF),
                                                   (0xC0FF8000, 1.5, 2.25, 13, 1.5, 0xFF10304A),
                                                   (0xFFFFFFFF, 0, 0, 32, 0.6, 0x00000000)):
                total += 1
                got, rc = host_ui(ui_tool, d, 34, 34, bg, [('icon', name, colour, x, y, size, weight)])
                want, rc2 = host_ctx(ctx_tool, d, 34, 34, bg, [('uic', PACK, name, int(size), NAMES.index(name),
                                                                 x, y, size, weight, [colour])])
                ok = got is not None and want is not None and bool((got == want).all())
                if not ok:
                    diff = -1 if got is None or want is None else int(np.abs(got.astype(int) - want.astype(int)).max())
                    print(f"FAIL  icon {name:14} size {size:4} exit {rc}/{rc2} max_diff={diff}")
                failed += not ok
        print(f"icons: {total - failed}/{total} identical to ugfx")
        total += 1
        _, rc = host_ui(ui_tool, d, 16, 16, 0, [('icon', 'no-such-icon', 0xFF000000, 0, 0, 16, 1.0)])
        failed += rc != 3
        print(f"{'ok  ' if rc == 3 else 'FAIL'}  unknown icon refused (exit {rc})")
        for name, w, h, th, bw, types in (("three buttons", 200, 60, 28, 0, [2, 1, 0]),
                                          ("with borders", 160, 80, 24, 3, [0]),
                                          ("menu and close", 120, 40, 20, 1, [3, 0]),
                                          ("small titlebar", 90, 30, 10, 0, [2, 1, 0]),
                                          ("big titlebar", 240, 90, 44, 2, [3, 2, 1, 0])):
            total += 1
            colours = (0xFF2D2D2D, 0xFF1A1A1A, 0xFF3D3D3D, 0xFFFFFFFF)
            got, rc = host_ui(ui_tool, d, w, h, 0xFF808080, [('decor', th, bw, *colours, types)])
            want, rc2 = host_ctx(ctx_tool, d, w, h, 0xFF808080, frame_calls(w, h, th, bw, *colours, types))
            ok = got is not None and want is not None and bool((got == want).all())
            diff = -1 if got is None or want is None else int(np.abs(got.astype(int) - want.astype(int)).max())
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  frame {name:16} {w}x{h} exit {rc}/{rc2} max_diff={diff}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

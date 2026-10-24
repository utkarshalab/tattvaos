#!/usr/bin/env python3
"""Check UIC icon packs: drawing, lookup by name and size, and validation.

Usage: uic_check.py <host_ctx binary>

Drawing: each icon is packed with tools/uic.py and drawn by ugfx_uic_draw
through host_ctx; the expected image is host_ctx running the context calls
the format defines for that icon (save; translate to the centred box;
scale; translate by -viewBox origin; for each FILL / STROKE the path at
q / 2^f units, the slot colour premultiplied, the rule or stroke style
with width x weight and miter limit 4; OPACITY as alpha x the entry alpha;
restore). The two must be byte-identical, also under an outer transform,
clip and alpha.

Lookup: names and design sizes resolve to the documented entry.
Validation: corrupt packs are refused when opened.

Development-machine tooling only; not part of any OS image.
"""
import math
import os
import struct
import subprocess
import sys
import tempfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
from ctx_check import encode  # noqa: E402
from uic import Icon, pack, quantise  # noqa: E402


def div255(x):
    x += 128
    return (x + (x >> 8)) >> 8


def premul(c):
    a = c >> 24
    return (a << 24) | sum(div255(((c >> s) & 255) * a) << s for s in (0, 8, 16))


def expected_calls(icon, x, y, size, weight, overrides, entry_alpha):
    """The context calls ugfx_uic_draw must make."""
    f = icon.fraction_bits()
    vx, vy, w, h = (float(np.float32(v)) for v in icon.viewbox)
    s = size / max(w, h)
    dx = x + (size - w * s) * 0.5
    dy = y + (size - h * s) * 0.5
    out = [('save',), ('translate', dx, dy), ('scale', s, s), ('translate', 0.0 - vx, 0.0 - vy), ('dash', 0, []),
           ('new_path',)]
    slots = list(overrides) + icon.slots[len(overrides):]
    unit = 1.0 / (1 << f)
    for c in icon.commands:
        op = c[0]
        if op in ('move', 'line', 'quad', 'cubic'):
            out.append((op, *(quantise(v, f) * unit for v in c[1:])))
        elif op == 'close':
            out.append(('close',))
        elif op == 'fill':
            out += [('fill_color', premul(slots[c[1]])), ('rule', c[2]), ('fill',), ('new_path',)]
        elif op == 'stroke':
            _, slot, join, cap, width = c
            out += [('stroke_color', premul(slots[slot])),
                    ('stroke_style', quantise(width, f) * unit * weight, 4.0, join, cap), ('stroke',), ('new_path',)]
        elif op == 'opacity':
            out.append(('alpha', div255(c[1] * entry_alpha)))
    return out + [('restore',)]


def circle(cx, cy, r, ccw=False):
    k = 0.5522847498 * r
    pts = [(cx + r, cy), (cx, cy + r), (cx - r, cy), (cx, cy - r)]
    if ccw:
        pts = pts[::-1]
    out = [('move', *pts[0])]
    for i in range(4):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % 4]
        t0 = ((y0 - cy) * (-1 if ccw else 1) * -1, (x0 - cx) * (-1 if ccw else 1))
        t1 = ((y1 - cy) * (-1 if ccw else 1) * -1, (x1 - cx) * (-1 if ccw else 1))
        n0, n1 = math.hypot(*t0) or 1, math.hypot(*t1) or 1
        out.append(('cubic', x0 + t0[0] / n0 * k, y0 + t0[1] / n0 * k, x1 - t1[0] / n1 * k, y1 - t1[1] / n1 * k, x1, y1))
    return out + [('close',)]


def icons():
    home = Icon("home", (0, 0, 24, 24), [0xFF333333], [
        ('move', 3, 11), ('line', 12, 3), ('line', 21, 11), ('line', 19, 11), ('line', 19, 21), ('line', 14, 21),
        ('line', 14, 15), ('line', 10, 15), ('line', 10, 21), ('line', 5, 21), ('line', 5, 11), ('close',),
        ('fill', 0, 0)])
    duo = Icon("duotone", (0, 0, 24, 24), [0xFF1060E0, 0xFF1060E0], [
        ('move', 2, 2), ('line', 22, 2), ('line', 22, 22), ('line', 2, 22), ('close',), ('opacity', 102), ('fill', 1, 0),
        ('opacity', 255)] + circle(12, 12, 6) + [('fill', 0, 0)])
    ring = Icon("ring", (0, 0, 24, 24), [0xFFE04020], circle(12, 12, 10) + circle(12, 12, 5.5) + [('fill', 0, 1)])
    line = Icon("pencil", (0, 0, 24, 24), [0xFF202020], [
        ('move', 4, 20), ('line', 8, 19), ('line', 19, 8), ('line', 16, 5), ('line', 5, 16), ('close',),
        ('stroke', 0, 1, 1, 2), ('move', 14, 7), ('line', 17, 10), ('stroke', 0, 1, 1, 2)])
    wide = Icon("wide", (0, 0, 24, 16), [0xFF208040], [('move', 1, 1), ('quad', 12, 20, 23, 1), ('close',), ('fill', 0, 0)])
    offset = Icon("offset", (-12, -12, 24, 24), [0xFF8020A0], circle(0, 0, 9) + [('fill', 0, 0),
                  ('move', -6, 0), ('line', 6, 0), ('stroke', 0, 0, 2, 1.5)])
    big = Icon("big-grid", (0, 0, 512, 512), [0xFF000000, 0xFFFFC000], [
        ('move', 256, 32), ('cubic', 400, 32, 480, 140, 480, 256), ('cubic', 480, 380, 380, 480, 256, 480),
        ('cubic', 130, 480, 32, 380, 32, 256), ('cubic', 32, 130, 120, 32, 256, 32), ('close',), ('fill', 1, 0),
        ('move', 160, 300), ('line', 256, 180), ('line', 352, 300), ('stroke', 0, 0, 0, 40)])
    sized16 = Icon("home", (0, 0, 16, 16), [0xFF333333], [('move', 1, 8), ('line', 8, 1), ('line', 15, 8),
                   ('line', 15, 15), ('line', 1, 15), ('close',), ('fill', 0, 0)], design_size=16)
    return [home, duo, ring, line, wide, offset, big, sized16]


def run(tool, d, cmds):
    sp, raw = os.path.join(d, "u.bin"), os.path.join(d, "u.raw")
    open(sp, "wb").write(encode(cmds))
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    return (open(raw, "rb").read() if r.returncode == 0 else None), r.returncode


def main():
    tool = os.path.abspath(sys.argv[1])
    ics = icons()
    data = pack(ics)
    order = sorted(ics, key=lambda i: (i.name.encode(), i.design_size))
    index = {(i.name, i.design_size): k for k, i in enumerate(order)}
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ugfx_uic.") as d:
        draws = [
            ("home", "home", 0, 4, 4, 24, 1.0, [], [], 255),
            ("home 16px variant", "home", 16, 2, 2, 28, 1.0, [], [], 255),
            ("duotone", "duotone", 0, 0, 0, 32, 1.0, [], [], 255),
            ("duotone recoloured", "duotone", 0, 8, 0, 32, 1.0, [0xFF20C060, 0xFFC02060], [], 255),
            ("ring even-odd", "ring", 0, 8, 1, 30, 1.0, [], [], 255),
            ("pencil weight 1", "pencil", 0, 0, 0, 32, 1.0, [], [], 255),
            ("pencil thin", "pencil", 0, 0, 0, 32, 0.5, [], [], 255),
            ("pencil bold", "pencil", 0, 0, 0, 32, 2.0, [], [], 255),
            ("pencil weight default", "pencil", 0, 0, 0, 32, 0.0, [], [], 255),
            ("wide centred", "wide", 0, 2, 2, 28, 1.0, [], [], 255),
            ("offset viewBox", "offset", 0, 10, 2, 28, 1.0, [0x80FF0000], [], 255),
            ("512 grid", "big-grid", 0, 8, 0, 32, 1.0, [], [], 255),
            ("tiny", "home", 0, 20, 12, 7, 1.0, [], [], 255),
            ("translucent override", "home", 0, 4, 4, 24, 1.0, [0x80FFFFFF], [], 255),
            ("under transform", "pencil", 0, 0, 0, 24, 1.0, [], [('translate', 30, 2), ('rotate', 0.4), ('scale', 1.2, 0.9)], 255),
            ("under clip and alpha", "duotone", 0, 4, 0, 32, 1.0, [], [('circle', 20, 16, 12), ('clip',), ('new_path',),
                                                                       ('alpha', 160)], 160),
            ("inside a layer", "ring", 0, 8, 1, 30, 1.5, [], [('begin_layer', 128)], 255),
        ]
        for name, icon_name, px, x, y, size, weight, cols, pre, entry_alpha in draws:
            total += 1
            entry = index.get((icon_name, 16)) if px >= 16 and (icon_name, 16) in index and px <= 16 else index[(icon_name, 0)]
            icon = order[entry]
            post = [('end_layer',)] if pre and pre[0][0] == 'begin_layer' else []
            got, rc = run(tool, d, pre + [('uic', data, icon_name, px, entry, x, y, size, weight, cols)] + post)
            want, rc2 = run(tool, d, pre + expected_calls(icon, x, y, size, weight if weight > 0 else 1.0, cols,
                                                          entry_alpha) + post)
            ok = got is not None and got == want
            diff = -1 if got is None or want is None else int(np.abs(np.frombuffer(got, np.uint8).astype(int)
                                                                     - np.frombuffer(want, np.uint8).astype(int)).max())
            painted = 0 if want is None else int((np.frombuffer(want, np.uint8).reshape(-1, 4) !=
                                                  np.frombuffer(run(tool, d, pre + post)[0], np.uint8).reshape(-1, 4)).any(axis=1).sum())
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  draw {name:24} exit {rc}/{rc2} max_diff={diff} painted={painted}")

        # lookup: a pack of names and design sizes
        look = [Icon(n, (0, 0, 24, 24), [0xFF000000], [('move', 0, 0), ('line', 1, 1), ('fill', 0, 0)], design_size=z)
                for n, z in (("a", 0), ("ab", 0), ("ab", 16), ("ab", 24), ("b", 16), ("b", 32), ("zz", 0))]
        lp = pack(look)
        lorder = sorted(look, key=lambda i: (i.name.encode(), i.design_size))
        li = {(i.name, i.design_size): k for k, i in enumerate(lorder)}
        for name, px, want in (("a", 0, li[("a", 0)]), ("ab", 0, li[("ab", 0)]), ("b", 0, li[("b", 32)]), ("a", 99, li[("a", 0)]), ("ab", 10, li[("ab", 16)]),
                               ("ab", 16, li[("ab", 16)]), ("ab", 20, li[("ab", 24)]), ("ab", 30, li[("ab", 0)]),
                               ("b", 8, li[("b", 16)]), ("b", 40, li[("b", 32)]), ("zz", 1, li[("zz", 0)]),
                               ("abc", 0, -1), ("", 0, -1), ("c", 0, -1), ("0", 0, -1), ("zzz", 0, -1)):
            total += 1
            _, rc = run(tool, d, [('uic', lp, name, px, want, 0, 0, 8, 1.0, [])])
            ok = rc == 0
            _, rc_wrong = run(tool, d, [('uic', lp, name, px, want + 1, 0, 0, 8, 1.0, [])])
            ok = ok and rc_wrong == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  find {name!r:6} at {px:3} -> {want:2}  exit {rc}/{rc_wrong}")

        # validation: corrupt packs are refused
        base = pack(ics[:2])
        good_body = lambda: bytearray(pack([ics[0]])[32 + 16 + 4:])   # noqa: E731

        def with_body(raw):
            return pack([Icon("x", (0, 0, 24, 24), [0], [])], raw_bodies={("x", 0): bytes(raw)})

        def body_bytes(vb=(0, 0, 24, 24), f=4, slots=(0xFF000000,), cmds=b"\x00", reserved=0):
            return struct.pack("<4fBBH", *vb, f, len(slots), reserved) + b"".join(struct.pack("<I", c) for c in slots) + cmds

        def patch(off, fmt, val):
            b = bytearray(base)
            struct.pack_into(fmt, b, off, val)
            return bytes(b)
        n = struct.unpack_from("<I", base, 8)[0]
        bad = [
            ("bad magic", b"UIX\x1a" + base[4:]),
            ("version 2", patch(4, "<H", 2)),
            ("flags", patch(6, "<H", 1)),
            ("truncated header", base[:20]),
            ("index past end", patch(8, "<I", 1000)),
            ("index misaligned", patch(12, "<I", 34)),
            ("strings past end", patch(20, "<I", 10 ** 6)),
            ("data past end", patch(28, "<I", 10 ** 6)),
            ("empty name", patch(32 + 12, "<H", 0)),
            ("name past strings", patch(32 + 12, "<H", 200)),
            ("body past data", patch(32 + 8, "<I", 10 ** 5)),
            ("unsorted", patch(32 + 16, "<I", 0) if n > 1 else base),   # entry 1 named "duot" < "duotone"
            ("duplicate", pack([ics[0], ics[0]])),
            ("no END", with_body(body_bytes(cmds=b"\x01\x00\x00\x00\x00"))),
            ("bad opcode", with_body(body_bytes(cmds=b"\x07\x00"))),
            ("operands cut", with_body(body_bytes(cmds=b"\x04\x00\x00"))),
            ("slot out of range", with_body(body_bytes(cmds=b"\x10\x01\x00\x00"))),
            ("bad rule", with_body(body_bytes(cmds=b"\x10\x00\x02\x00"))),
            ("bad join", with_body(body_bytes(cmds=b"\x11\x00\x03\x10\x00\x00"))),
            ("bad cap", with_body(body_bytes(cmds=b"\x11\x00\x30\x10\x00\x00"))),
            ("zero width", with_body(body_bytes(cmds=b"\x11\x00\x00\x00\x00\x00"))),
            ("negative width", with_body(body_bytes(cmds=b"\x11\x00\x00\x00\xff\xff\x00"))),
            ("no slots", with_body(body_bytes(slots=()))),
            ("17 slots", with_body(body_bytes(slots=(0,) * 17))),
            ("15 fraction bits", with_body(body_bytes(f=15))),
            ("reserved set", with_body(body_bytes(reserved=1))),
            ("zero width viewBox", with_body(body_bytes(vb=(0, 0, 0, 24)))),
            ("NaN viewBox", with_body(body_bytes(vb=(math.nan, 0, 24, 24)))),
            ("infinite viewBox", with_body(body_bytes(vb=(0, 0, 24, math.inf)))),
            ("body too short", with_body(b"\0" * 12)),
        ]
        for name, blob in bad:
            total += 1
            _, rc = run(tool, d, [('uic', blob, "x", 0, -2, 0, 0, 8, 1.0, [])])
            ok = rc == 5
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  refuse {name:22} exit={rc}")
        total += 1
        _, rc = run(tool, d, [('uic', with_body(body_bytes()), "x", 0, 0, 0, 0, 8, 1.0, [])])
        failed += rc != 0
        print(f"{'ok  ' if rc == 0 else 'FAIL'}  accept minimal body      exit={rc}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

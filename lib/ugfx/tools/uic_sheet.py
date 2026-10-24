#!/usr/bin/env python3
"""Render icons from a UIC pack into a PNG contact sheet, through ugfx.

    uic_sheet.py <host_ctx> <pack.uic> <out.png> [--size 32] [--cols 16]
                 [--count 128] [--start 0] [--colour RRGGBB] [--weight 1]

The icons are drawn by ugfx_uic_draw (tests/host/host_ctx) on a white
sheet, in index order. Development-machine tooling only.
"""
import os
import struct
import subprocess
import sys
import tempfile
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "host"))
import ctx_check  # noqa: E402
from uic import Icon, pack  # noqa: E402


def read_pack(data):
    """Icons of a pack, decoded back into uic.Icon (raw bodies kept)."""
    _, _, _, n, io, so, ss, do, ds = struct.unpack_from("<4sHHIIIIII", data)
    out = []
    for i in range(n):
        no, bo, bs, nl, size = struct.unpack_from("<IIIHH", data, io + 16 * i)
        out.append((data[so + no:so + no + nl].decode(), size, data[do + bo:do + bo + bs]))
    return out


def png(path, w, h, bgra):
    rows = b"".join(b"\0" + bytes(px for i in range(w) for px in (bgra[(y * w + i) * 4 + 2], bgra[(y * w + i) * 4 + 1],
                                                                    bgra[(y * w + i) * 4], bgra[(y * w + i) * 4 + 3]))
                    for y in range(h))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                           + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def main(argv):
    tool, pack_path, out = argv[:3]
    opts = dict(size=32, cols=16, count=128, start=0, colour="202020", weight=1.0)
    rest = argv[3:]
    while rest:
        k = rest.pop(0).lstrip("-")
        opts[k] = type(opts[k])(rest.pop(0))
    entries = read_pack(open(pack_path, "rb").read())[opts["start"]:opts["start"] + opts["count"]]
    size, cols = opts["size"], opts["cols"]
    cell = size + size // 4
    rows = (len(entries) + cols - 1) // cols
    W, H = cols * cell, max(rows, 1) * cell
    ctx_check.W, ctx_check.H, ctx_check.BG = W, H, 0xFFFFFFFF
    # a small pack holding just these icons (raw bodies, unchanged)
    icons = [Icon(f"i{k:05d}", (0, 0, 1, 1), [0], [], 0) for k in range(len(entries))]
    sub = pack(icons, raw_bodies={(f"i{k:05d}", 0): body for k, (_, _, body) in enumerate(entries)})
    colour = 0xFF000000 | int(opts["colour"], 16)
    cmds = [('uic', sub, f"i{k:05d}", 0, k, (k % cols) * cell + (cell - size) / 2, (k // cols) * cell + (cell - size) / 2,
             size, opts["weight"], [colour]) for k in range(len(entries))]
    with tempfile.TemporaryDirectory(prefix="uic_sheet.") as d:
        sp, raw = os.path.join(d, "s.bin"), os.path.join(d, "s.raw")
        open(sp, "wb").write(ctx_check.encode(cmds))
        r = subprocess.run([tool, sp, raw], capture_output=True, timeout=600)
        if r.returncode:
            sys.exit(f"host_ctx failed ({r.returncode})")
        png(out, W, H, open(raw, "rb").read())
    print(f"{out}: {len(entries)} icons, {W}x{H}: " + ", ".join(n for n, _, _ in entries[:8]) + " ...")


if __name__ == "__main__":
    main(sys.argv[1:])

#!/usr/bin/env python3
"""Check Canvas's image encoders against a reference decoder (Pillow).

Usage: encode_check.py <host_encode binary> <host_decode binary>

Synthetic images (opaque, see-through, odd sizes) are written as PNG, then
host_encode decodes each (image_decode) and encodes it again:
  PNG and QOI must come back from Pillow with exactly the pixels Canvas
  holds (premultiplied, as image_decode keeps them);
  JPEG, at several qualities, must decode with Pillow and with Canvas's own
  decoder, as close to the source as Pillow's encoder gets at the same
  quality and subsampling (PSNR at most 1.0 dB below, or above 45 dB where
  one level's rounding is the difference), and no more than 1.25 times the
  size.

Development-machine test tooling only; not part of any OS image.
"""

import io
import math
import os
import struct
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_images import synth  # noqa: E402

JPEG_QUALITIES = (30, 50, 75, 90, 100)
PSNR_MARGIN = 1.0
SIZE_MARGIN = 1.25
NEAR_EXACT = 45.0          # above it a level's rounding is all that differs


def premultiplied(rgba):
    a = rgba[..., 3:4].astype(np.int64)
    t = rgba[..., :3].astype(np.int64) * a + 128
    out = rgba.astype(np.int64).copy()
    out[..., :3] = (t + (t >> 8)) >> 8
    return out


def psnr(a, b):
    mse = np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2)
    return math.inf if mse == 0 else 10 * math.log10(255.0 ** 2 / mse)


def canvas_decode(tool, path, out):
    r = subprocess.run([tool, path, out], capture_output=True, timeout=60)
    if r.returncode:
        return None
    data = open(out, "rb").read()
    w, h, stride, fmt = struct.unpack_from("<4I", data)
    px = np.frombuffer(data, dtype=np.uint8, offset=16).reshape(h, w, 4)
    return px[..., [2, 1, 0]].astype(np.int64)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    encode, decode = (os.path.abspath(a) for a in sys.argv[1:])
    images = [("photo", synth(200, 150, 7)), ("odd", synth(37, 23, 17)),
              ("alpha", synth(96, 80, 11, alpha=True)), ("one", synth(1, 1, 3))]
    failed = 0
    with tempfile.TemporaryDirectory(prefix="canvas_enc.") as d:
        for name, im in images:
            src = os.path.join(d, name + ".png")
            im.save(src)
            held = premultiplied(np.asarray(im.convert("RGBA")))
            for fmt, ext in (("p", "png"), ("q", "qoi")):
                out = os.path.join(d, f"{name}.{ext}")
                r = subprocess.run([encode, src, out, fmt], capture_output=True, timeout=60)
                if r.returncode:
                    print(f"FAIL  {name}.{ext}: host_encode exit {r.returncode}")
                    failed += 1
                    continue
                got = premultiplied(np.asarray(Image.open(out).convert("RGBA")))
                ok = np.array_equal(got, held)
                failed += not ok
                print(f"{'ok  ' if ok else 'FAIL'}  {name}.{ext:4}  "
                      f"{'exact' if ok else 'differs'}  {os.path.getsize(out)} bytes")
            rgb = held[..., :3]                  # see-through: over black
            source = Image.fromarray(rgb.astype(np.uint8), "RGB")
            for q in JPEG_QUALITIES:
                out = os.path.join(d, f"{name}_q{q}.jpg")
                r = subprocess.run([encode, src, out, "j", str(q)],
                                   capture_output=True, timeout=60)
                if r.returncode:
                    print(f"FAIL  {name} q{q}: host_encode exit {r.returncode}")
                    failed += 1
                    continue
                ours = np.asarray(Image.open(out).convert("RGB")).astype(np.int64)
                b = io.BytesIO()
                source.save(b, "JPEG", quality=q, subsampling=2)
                theirs = np.asarray(Image.open(io.BytesIO(b.getvalue())).convert("RGB"))
                p_ours, p_theirs = psnr(ours, rgb), psnr(theirs, rgb)
                size, their_size = os.path.getsize(out), len(b.getvalue())
                own = canvas_decode(decode, out, os.path.join(d, "o.raw"))
                problems = []
                if p_ours < min(p_theirs - PSNR_MARGIN, NEAR_EXACT):
                    problems.append("worse than the reference encoder")
                if size > their_size * SIZE_MARGIN:
                    problems.append("larger than the reference encoder's")
                if own is None or psnr(own, ours) < 45:
                    problems.append("Canvas's decoder does not read it as Pillow does")
                failed += bool(problems)
                print(f"{'FAIL' if problems else 'ok  '}  {name} q{q:<3}  {p_ours:6.2f} dB "
                      f"(reference {p_theirs:6.2f})  {size} bytes (reference {their_size})"
                      + (f"  {'; '.join(problems)}" if problems else ""))
    print("encode_check: " + ("passed" if not failed else f"{failed} failures"))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

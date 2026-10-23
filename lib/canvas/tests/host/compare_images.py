#!/usr/bin/env python3
"""Compare Canvas image decoders against a reference decoder (Pillow).

Usage: compare_images.py <host_decode binary> [image ...]

With no images, a corpus is generated into a temporary directory: WebP lossy
(several sizes, qualities and filter settings), WebP with alpha, WebP
lossless, and PNG/JPEG/GIF/BMP/TGA/PPM variants. Each file is decoded by
Canvas (host_decode) and by Pillow; PSNR over RGBA is reported. Canvas
output is premultiplied BGRA (decision 0002), so the reference is
premultiplied with the same rounding, round(c * a / 255), before comparing.

Lossless formats must match exactly. Lossy formats are compared with a PSNR
floor because chroma upsampling and YUV->RGB rounding legitimately differ
between decoders; a broken decoder lands far below the floor.

Development-machine test tooling only; not part of any OS image.
"""
import math
import os
import struct
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image

LOSSY_PSNR_FLOOR = 30.0


def synth(w, h, seed, alpha=False):
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w]
    r = (x * 255 // max(w - 1, 1)).astype(np.uint8)
    g = (y * 255 // max(h - 1, 1)).astype(np.uint8)
    b = ((x + y) * 7 % 256).astype(np.uint8)
    img = np.stack([r, g, b], axis=-1).astype(np.int16)
    # Hard edges and noise exercise prediction modes, B_PRED and the loop filter.
    img[h // 3 : h // 2, w // 4 : w // 2] = [250, 20, 30]
    img += rng.integers(-12, 13, size=img.shape, dtype=np.int16)
    img = np.clip(img, 0, 255).astype(np.uint8)
    if alpha:
        a = ((x * 3 + y * 5) % 256).astype(np.uint8)
        a[: h // 4] = 255
        a[-h // 4 :] = 0
        return Image.fromarray(np.dstack([img, a]), "RGBA")
    return Image.fromarray(img, "RGB")


def build_corpus(d):
    cases = []

    def add(name, kind, save):
        path = os.path.join(d, name)
        save(path)
        cases.append((path, kind))

    for w, h in [(1, 1), (16, 16), (17, 13), (33, 47), (64, 64), (127, 95), (320, 240)]:
        for q in (5, 50, 95):
            im = synth(w, h, w * 31 + h + q)
            add(f"lossy_{w}x{h}_q{q}.webp", "lossy",
                lambda p, im=im, q=q: im.save(p, "WEBP", quality=q, method=4))
    im = synth(200, 150, 7)
    for m in (0, 6):
        add(f"lossy_method{m}.webp", "lossy",
            lambda p, m=m: im.save(p, "WEBP", quality=75, method=m))
    add("lossy_sharp_yuv.webp", "lossy",
        lambda p: im.save(p, "WEBP", quality=75, use_sharp_yuv=True))
    ima = synth(96, 80, 11, alpha=True)
    add("lossy_alpha.webp", "lossy",
        lambda p: ima.save(p, "WEBP", quality=80, alpha_quality=100))
    add("lossless.webp", "exact", lambda p: im.save(p, "WEBP", lossless=True))
    add("lossless_alpha.webp", "exact",
        lambda p: ima.save(p, "WEBP", lossless=True, exact=True))

    add("rgb.png", "exact", lambda p: im.save(p, "PNG"))
    add("rgba.png", "exact", lambda p: ima.save(p, "PNG"))
    add("interlaced.png", "exact", lambda p: im.save(p, "PNG", interlace=1))
    add("palette.png", "exact", lambda p: im.convert("P").save(p, "PNG"))
    add("gray.png", "exact", lambda p: im.convert("L").save(p, "PNG"))
    add("baseline.jpg", "lossy", lambda p: im.save(p, "JPEG", quality=90))
    add("progressive.jpg", "lossy",
        lambda p: im.save(p, "JPEG", quality=90, progressive=True))
    add("gray.jpg", "lossy", lambda p: im.convert("L").save(p, "JPEG", quality=90))
    add("subsample444.jpg", "lossy",
        lambda p: im.save(p, "JPEG", quality=90, subsampling=0))
    add("image.gif", "exact", lambda p: im.convert("P").save(p, "GIF"))
    add("image.bmp", "exact", lambda p: im.save(p, "BMP"))
    add("image.tga", "exact", lambda p: im.save(p, "TGA"))
    add("image.ppm", "exact", lambda p: im.save(p, "PPM"))
    return cases


def canvas_decode(tool, path, out):
    r = subprocess.run([tool, path, out], capture_output=True, timeout=60)
    if r.returncode != 0:
        return None, f"host_decode exit {r.returncode}"
    with open(out, "rb") as f:
        data = f.read()
    w, h, stride, fmt = struct.unpack_from("<4I", data)
    px = np.frombuffer(data, dtype=np.uint8, offset=16)
    if px.size != w * h * 4:
        return None, f"short output ({px.size} bytes for {w}x{h})"
    bgra = px.reshape(h, w, 4).astype(np.int64)
    return bgra[..., [2, 1, 0, 3]], None


def reference_decode(path):
    ref = np.asarray(Image.open(path).convert("RGBA")).astype(np.int64)
    t = ref[..., :3] * ref[..., 3:4] + 128
    ref[..., :3] = (t + (t >> 8)) >> 8
    return ref


def psnr(a, b):
    mse = np.mean((a - b).astype(np.float64) ** 2)
    return math.inf if mse == 0 else 10 * math.log10(255.0 ** 2 / mse)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    tool = os.path.abspath(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="canvas_cmp.") as d:
        if len(sys.argv) > 2:
            cases = [(p, "lossy" if p.lower().endswith((".jpg", ".jpeg", ".webp")) else "exact")
                     for p in sys.argv[2:]]
        else:
            cases = build_corpus(d)
        out = os.path.join(d, "out.raw")
        failed = 0
        for path, kind in cases:
            name = os.path.basename(path)
            got, err = canvas_decode(tool, path, out)
            ref = reference_decode(path)
            if err is None and got.shape != ref.shape:
                err = f"size {got.shape[1]}x{got.shape[0]} != {ref.shape[1]}x{ref.shape[0]}"
            if err:
                print(f"FAIL  {name:28} {err}")
                failed += 1
                continue
            p = psnr(got, ref)
            maxdiff = int(np.max(np.abs(got - ref)))
            ok = p == math.inf if kind == "exact" else p >= LOSSY_PSNR_FLOOR
            failed += not ok
            shown = "exact" if p == math.inf else f"{p:6.2f} dB"
            print(f"{'ok  ' if ok else 'FAIL'}  {name:28} {shown:>9}  maxdiff={maxdiff}")
        print(f"{len(cases) - failed}/{len(cases)} passed")
        sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

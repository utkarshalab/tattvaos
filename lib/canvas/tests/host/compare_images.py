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
import random
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


def write_bmp(path, w, h, bpp, pixels, comp=0, palette=None, masks=None,
              hdr=40, topdown=False):
    """Hand-built BMP for layouts the reference encoder does not write.
    pixels: raw pixel array bytes (rows padded to 4 bytes, bottom-up unless
    topdown) or an RLE stream."""
    pal = b"".join(bytes((b, g, r) if hdr == 12 else (b, g, r, 0))
                   for r, g, b in (palette or []))
    if hdr == 12:
        info = struct.pack("<IHHHH", 12, w, h, 1, bpp)
    else:
        info = struct.pack("<IiiHHIIiiII", hdr, w, -h if topdown else h, 1, bpp,
                           comp, len(pixels), 2835, 2835, len(palette or []), 0)
        if masks:
            info += struct.pack("<" + "I" * len(masks), *masks)
        info += bytes(hdr - len(info)) if len(info) < hdr else b""
    off = 14 + len(info) + len(pal)
    head = struct.pack("<2sIHHI", b"BM", off + len(pixels), 0, 0, off)
    with open(path, "wb") as f:
        f.write(head + info + pal + pixels)


def pack_rows(rows, bpp):
    out = b""
    for row in rows:
        if bpp >= 8:
            b = b"".join(v.to_bytes(bpp // 8, "little") for v in row)
        else:
            bits = "".join(format(v, f"0{bpp}b") for v in row)
            bits += "0" * (-len(bits) % 8)
            b = bytes(int(bits[i:i + 8], 2) for i in range(0, len(bits), 8))
        out += b + bytes(-len(b) % 4)
    return out


def rle_encode(rows, four):
    """RLE8/RLE4 stream (rows bottom-up): runs, one absolute run, a delta."""
    out = bytearray()
    resume = None
    for y, row in enumerate(rows):
        x = 0
        if resume is not None:
            if y < resume[1]:
                continue              # row skipped by the delta
            if y == resume[1]:
                x = resume[0]
        if y == 1 and len(row) >= 6:  # absolute mode for the first pixels
            # RLE4 uses an even count: the reference decoder drops the last
            # pixel of odd-length RLE4 absolute runs (reads n // 2 bytes).
            n = 6 if four else 5
            if four:
                vals = row[:n] + [0] * (n % 2)
                data = bytes((vals[i] << 4) | vals[i + 1] for i in range(0, len(vals), 2))
            else:
                data = bytes(row[:n])
            out += bytes((0, n)) + data + bytes(len(data) & 1)
            x = n
        while x < len(row):
            v, n = row[x], 1
            while x + n < len(row) and row[x + n] == v and n < 255:
                n += 1
            out += bytes((n, (v << 4) | v if four else v))
            x += n
        out += b"\x00\x00"
        if y == 2 and len(rows) > 4:
            out += b"\x00\x02\x03\x02"  # delta: from (0, 3) to (3, 5)
            resume = (3, 5)
    return bytes(out) + b"\x00\x01"


def bmp_variants(add, rng):
    w, h = 37, 21
    pal = [(rng.randrange(256), rng.randrange(256), rng.randrange(256)) for _ in range(256)]
    for bpp in (1, 2, 4, 8):
        rows = [[rng.randrange(1 << bpp) for _ in range(w)] for _ in range(h)]
        if bpp == 2:  # reference decoders do not read 2-bit BMP; keep the
            continue  # code path covered by the unit suite instead
        add(f"pal{bpp}.bmp", "exact", lambda p, rows=rows, bpp=bpp:
            write_bmp(p, w, h, bpp, pack_rows(rows, bpp), palette=pal[:1 << bpp]))
    px = [[rng.randrange(1 << 15) for _ in range(w)] for _ in range(h)]
    add("rgb555.bmp", "exact", lambda p: write_bmp(p, w, h, 16, pack_rows(px, 16)))
    add("rgb565.bmp", "exact", lambda p: write_bmp(
        p, w, h, 16, pack_rows([[v * 2 + (v & 1) for v in r] for r in px], 16),
        comp=3, masks=(0xF800, 0x07E0, 0x001F)))
    px32 = [[rng.randrange(1 << 32) for _ in range(w)] for _ in range(h)]
    add("bgra_fields.bmp", "exact", lambda p: write_bmp(
        p, w, h, 32, pack_rows(px32, 32), comp=3,
        masks=(0xFF0000, 0xFF00, 0xFF, 0xFF000000), hdr=56))
    px24 = [[rng.randrange(1 << 24) for _ in range(w)] for _ in range(h)]
    add("core24.bmp", "exact", lambda p: write_bmp(p, w, h, 24, pack_rows(px24, 24), hdr=12))
    add("topdown24.bmp", "exact", lambda p: write_bmp(
        p, w, h, 24, pack_rows(px24[::-1], 24), topdown=True))
    rows8 = [[rng.choice((3, 3, 3, 7, 200)) for _ in range(w)] for _ in range(h)]
    add("rle8.bmp", "exact", lambda p: write_bmp(p, w, h, 8, rle_encode(rows8, False),
                                                 comp=1, palette=pal))
    rows4 = [[rng.choice((1, 1, 1, 5, 14)) for _ in range(w)] for _ in range(h)]
    add("rle4.bmp", "exact", lambda p: write_bmp(p, w, h, 4, rle_encode(rows4, True),
                                                 comp=2, palette=pal[:16]))


def write_farbfeld(path, im):
    """16-bit RGBA, big endian; each 8-bit value doubled (v * 257) so it maps back exactly."""
    rgba = np.asarray(im.convert("RGBA")).astype(np.uint32)
    h, w = rgba.shape[:2]
    with open(path, "wb") as f:
        f.write(b"farbfeld" + struct.pack(">II", w, h) + (rgba * 257).astype(">u2").tobytes())


def read_farbfeld(path):
    with open(path, "rb") as f:
        data = f.read()
    w, h = struct.unpack_from(">II", data, 8)
    return (np.frombuffer(data, ">u2", offset=16).reshape(h, w, 4) >> 8).astype(np.int64)


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
    noisy = synth(300, 200, 3).convert("P", palette=Image.ADAPTIVE, colors=256)
    add("noisy.gif", "exact", lambda p: noisy.save(p, "GIF"))   # table fills, clears
    add("interlaced.gif", "exact", lambda p: noisy.save(p, "GIF", interlace=True))
    two = synth(31, 17, 5).convert("1").convert("P")
    add("twocolor.gif", "exact", lambda p: two.save(p, "GIF"))  # minimum code size 2
    add("transparent.gif", "exact", lambda p: noisy.save(p, "GIF", transparency=5))
    add("image.bmp", "exact", lambda p: im.save(p, "BMP"))
    add("gray.bmp", "exact", lambda p: im.convert("L").save(p, "BMP"))
    add("mono.bmp", "exact", lambda p: im.convert("1").save(p, "BMP"))
    bmp_variants(add, random.Random(7))
    add("image.tga", "exact", lambda p: im.save(p, "TGA"))
    add("image.ppm", "exact", lambda p: im.save(p, "PPM"))
    add("image.ff", "exact", lambda p: write_farbfeld(p, ima))
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
    if path.endswith(".ff"):
        ref = read_farbfeld(path)
    else:
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

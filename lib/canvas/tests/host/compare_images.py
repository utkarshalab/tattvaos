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
floor because IDCT and YUV->RGB rounding legitimately differ between
decoders; a broken decoder lands far below the floor.

Development-machine test tooling only; not part of any OS image.
"""
import io
import math
import os
import random
import struct
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageCms, ImageOps

# Canvas upsamples chroma as the reference does, so what is left is the
# IDCT's and the colour conversion's rounding: every lossy file is above
# 51 dB. At 30, 4:2:0 JPEG upsampled without interpolation (about 29 dB)
# passed some files.
LOSSY_PSNR_FLOOR = 45.0

# Corpus files Canvas cannot decode yet, with the reason. Canvas must refuse
# each one: that is reported on every run and does not fail it. One decoded
# wrongly, or one that starts passing (so that its entry is removed), fails.
# Tracked in docs/ROADMAP.md (MED-20).
KNOWN_GAPS = {}


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
    # MED-20: the default scripts refine DC and AC by successive approximation
    add("progressive_gray.jpg", "lossy",
        lambda p: im.convert("L").save(p, "JPEG", quality=90, progressive=True))
    add("progressive444.jpg", "lossy",
        lambda p: im.save(p, "JPEG", quality=90, progressive=True, subsampling=0))
    add("progressive_restart.jpg", "lossy",
        lambda p: im.save(p, "JPEG", quality=90, progressive=True, restart_marker_blocks=1))
    add("subsample444.jpg", "lossy",
        lambda p: im.save(p, "JPEG", quality=90, subsampling=0))
    add("subsample422.jpg", "lossy",
        lambda p: im.save(p, "JPEG", quality=90, subsampling=1))
    odd = synth(37, 23, 17)    # chroma interpolated up to odd edges
    add("odd420.jpg", "lossy", lambda p: odd.save(p, "JPEG", quality=90, subsampling=2))
    add("odd422.jpg", "lossy", lambda p: odd.save(p, "JPEG", quality=90, subsampling=1))
    add("odd_progressive.jpg", "lossy",
        lambda p: odd.save(p, "JPEG", quality=90, progressive=True))
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
    vp8l_variants(add)
    icc_variants(add)
    format_variants(add)
    # MED-03: every EXIF orientation but 1, an image wider than it is tall,
    # in each format whose decode is turned upright by it
    turned = synth(37, 23, 13)
    for o in range(2, 9):
        exif = Image.Exif()
        exif[0x0112] = o
        b = exif.tobytes()
        add(f"orient{o}.png", "exact", lambda p, b=b: turned.save(p, "PNG", exif=b))
        add(f"orient{o}.jpg", "lossy",
            lambda p, b=b: turned.save(p, "JPEG", quality=90, exif=b))
        add(f"orient{o}.webp", "exact",
            lambda p, b=b: turned.save(p, "WEBP", lossless=True, exif=b))
    return cases


def vp8l_variants(add):
    """Lossless WebP by what each image makes the encoder use: palettes of
    every index width, the predictor, colour transform and cache on gradients
    and noise, long distances, and entropy groups on a large image."""
    r = random.Random(13)

    def image(w, h, pixel):
        im = Image.new("RGB", (w, h))
        im.putdata([pixel(x, y) for y in range(h) for x in range(w)])
        return im

    def noise(x, y):
        return (r.randrange(256), r.randrange(256), r.randrange(256))

    def gradient(x, y):
        return (x & 255, y & 255, (x + y) * 2 & 255)

    def regions(x, y):
        return (x // 64 * 80 & 255, y // 64 * 80 & 255, (x // 8 + y // 8) * 40 & 255)

    variants = [("solid", 16, 16, lambda x, y: (10, 200, 30)),
                ("gradient", 200, 150, gradient),
                ("noise", 64, 64, noise),
                ("regions", 640, 480, regions)]
    for colours in (2, 4, 16, 100):
        palette = [noise(0, 0) for _ in range(colours)]
        variants.append((f"palette{colours}", 48, 32,
                         lambda x, y, p=palette: p[r.randrange(len(p))]))
    for name, w, h, pixel in variants:
        im = image(w, h, pixel)
        for method in (0, 6):
            add(f"vp8l_{name}_m{method}.webp", "exact",
                lambda p, im=im, m=method: im.save(p, "WEBP", lossless=True,
                                                   quality=100, method=m))


D50 = (0.9642, 1.0, 0.8249)


def colorants(primaries, white):
    """The D50 (Bradford-adapted) colorants of RGB primaries and a white,
    each an xy chromaticity: the matrix columns of an ICC RGB profile."""
    def xyz(x, y):
        return np.array([x / y, 1.0, (1 - x - y) / y])
    p = np.array([xyz(*c) for c in primaries]).T
    w = xyz(*white)
    m = p * np.linalg.solve(p, w)
    brad = np.array([[0.8951, 0.2664, -0.1614], [-0.7502, 1.7135, 0.0367],
                     [0.0389, -0.0685, 1.0296]])
    adapt = np.linalg.inv(brad) @ np.diag((brad @ np.array(D50)) / (brad @ w)) @ brad
    return [tuple(c) for c in (adapt @ m).T]


def make_icc(curves, xyz=None):
    """An ICC v2 display profile of the matrix/TRC kind: RGB with three
    colorants (xyz) and three curves, or grey with one. A curve is
    ("gamma", g), ("table", [0..65535, ...]) or ("para", function, [params])."""
    def s15(v):
        return struct.pack(">i", round(v * 65536))

    def tag_xyz(v):
        return b"XYZ " + bytes(4) + b"".join(s15(c) for c in v)

    def tag_curve(c):
        if c[0] == "gamma":
            return b"curv" + bytes(4) + struct.pack(">IH", 1, round(c[1] * 256)) + bytes(2)
        if c[0] == "table":
            t = b"curv" + bytes(4) + struct.pack(">I", len(c[1]))
            t += b"".join(struct.pack(">H", v) for v in c[1])
            return t + bytes(-len(t) % 4)
        return b"para" + bytes(4) + struct.pack(">HH", c[1], 0) + b"".join(s15(v) for v in c[2])

    desc = b"desc" + bytes(4) + struct.pack(">I", 5) + b"test\0" + bytes(4 + 4 + 2 + 1 + 67)
    desc += bytes(-len(desc) % 4)
    tags = [(b"desc", desc), (b"wtpt", tag_xyz(D50))]
    if xyz is None:
        tags.append((b"kTRC", tag_curve(curves[0])))
    else:
        for n, v in zip((b"rXYZ", b"gXYZ", b"bXYZ"), xyz):
            tags.append((n, tag_xyz(v)))
        for n, c in zip((b"rTRC", b"gTRC", b"bTRC"), curves):
            tags.append((n, tag_curve(c)))
    offset = 128 + 4 + 12 * len(tags)
    table, data = b"", b""
    for name, body in tags:
        table += name + struct.pack(">II", offset + len(data), len(body))
        data += body
    size = offset + len(data)
    header = struct.pack(">I", size) + bytes(4) + struct.pack(">I", 0x02100000)
    header += b"mntr" + (b"GRAY" if xyz is None else b"RGB ") + b"XYZ " + bytes(12)
    header += b"acsp" + bytes(24) + b"".join(s15(c) for c in D50)
    header += bytes(128 - len(header))
    return header + struct.pack(">I", len(tags)) + table + data


def icc_variants(add):
    """COL-02: images with embedded profiles, turned into sRGB; the
    reference is the colour management library's sRGB transform."""
    d65 = (0.3127, 0.3290)
    p3 = colorants([(0.680, 0.320), (0.265, 0.690), (0.150, 0.060)], d65)
    adobe = colorants([(0.640, 0.330), (0.210, 0.710), (0.150, 0.060)], d65)
    rec2020 = colorants([(0.708, 0.292), (0.170, 0.797), (0.131, 0.046)], d65)
    srgb_curve = ("para", 3, [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045])
    table = ("table", [round(65535 * (i / 1023) ** 1.8) for i in range(1024)])
    big = ("table", [round(65535 * (i / 29999) ** 2.0) for i in range(30000)])
    im = synth(57, 41, 31)
    grey = im.convert("L")

    def save(name, image, fmt, icc, **kw):
        add(name, "lossy", lambda p: image.save(p, fmt, icc_profile=icc, **kw))
    save("icc_p3.png", im, "PNG", make_icc([srgb_curve] * 3, p3))
    save("icc_adobe.jpg", im, "JPEG", make_icc([("gamma", 2.2)] * 3, adobe), quality=95)
    save("icc_rec2020_table.webp", im, "WEBP", make_icc([table] * 3, rec2020),
         lossless=True)
    save("icc_grey.png", grey, "PNG", make_icc([("para", 0, [1.8])]))
    save("icc_para4.tif", im, "TIFF", make_icc(
        [("para", 4, [2.2, 0.95, 0.05, 0.08, 0.06, 0.0, 0.01])] * 3, p3))
    save("icc_srgb.png", im, "PNG",
         ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())
    save("icc_two_chunks.jpg", im, "JPEG", make_icc([big] * 3, adobe), quality=95)


def format_variants(add):
    """QA-09: every other format Canvas decodes that the reference library
    writes, in the encodings it writes: TIFF uncompressed, LZW, PackBits and
    deflate, RGBA, grey, 16-bit grey and palette; PCX RGB, palette and grey;
    ICO; DDS uncompressed and block-compressed (DXT1, DXT5, BC5 with the
    DX10 header; BC4 and BC5 also under the older ATI1 and ATI2 codes,
    made from it); QOI;
    PGM and PBM; TGA run-length RGBA and grey; BMP with alpha; PNG 16-bit
    grey and grey with alpha."""
    im = synth(61, 37, 41)
    ima = synth(61, 37, 43, alpha=True)
    grey = im.convert("L")
    grey16 = Image.fromarray(np.asarray(grey).astype(np.uint16) * 257)
    for comp in ("raw", "tiff_lzw", "packbits", "tiff_adobe_deflate"):
        add(f"tiff_{comp}.tif", "exact", lambda p, c=comp: im.save(p, "TIFF", compression=c))
    add("tiff_rgba.tif", "exact", lambda p: ima.save(p, "TIFF"))
    add("tiff_grey.tif", "exact", lambda p: grey.save(p, "TIFF", compression="tiff_lzw"))
    add("tiff_grey16.tif", "exact", lambda p: grey16.save(p, "TIFF"))
    add("tiff_palette.tif", "exact", lambda p: im.convert("P").save(p, "TIFF"))
    add("image.pcx", "exact", lambda p: im.save(p, "PCX"))
    add("palette.pcx", "exact", lambda p: im.convert("P").save(p, "PCX"))
    add("grey.pcx", "exact", lambda p: grey.save(p, "PCX"))
    add("image.ico", "exact", lambda p: ima.resize((48, 48)).save(p, "ICO", sizes=[(48, 48)]))
    add("rgba.dds", "exact", lambda p: ima.save(p, "DDS"))
    add("dxt1.dds", "exact", lambda p: im.convert("RGBA").save(p, "DDS", pixel_format="DXT1"))
    add("dxt5.dds", "exact", lambda p: ima.save(p, "DDS", pixel_format="DXT5"))
    add("bc5.dds", "exact", lambda p: im.save(p, "DDS", pixel_format="BC5"))

    def bc5_as(path, fourcc, red_only):
        """The BC5 file's blocks under the older header (FourCC, no DX10
        part) or, red_only, as BC4 (each block's first 8 bytes)."""
        b = io.BytesIO()
        im.save(b, "DDS", pixel_format="BC5")
        data = b.getvalue()
        blocks = data[148:]
        if red_only:
            blocks = b"".join(blocks[i:i + 8] for i in range(0, len(blocks), 16))
        header = bytearray(data[:128])
        header[84:88] = fourcc
        open(path, "wb").write(bytes(header) + blocks)
    add("ati2.dds", "exact", lambda p: bc5_as(p, b"ATI2", False))
    add("ati1.dds", "exact", lambda p: bc5_as(p, b"ATI1", True))
    add("image.qoi", "exact", lambda p: im.save(p, "QOI"))
    add("rgba.qoi", "exact", lambda p: ima.save(p, "QOI"))
    add("grey.pgm", "exact", lambda p: grey.save(p, "PPM"))
    add("mono.pbm", "exact", lambda p: grey.convert("1").save(p, "PPM"))
    add("rle_rgba.tga", "exact", lambda p: ima.save(p, "TGA", compression="tga_rle"))
    add("grey.tga", "exact", lambda p: grey.save(p, "TGA"))
    add("rgba.bmp", "exact", lambda p: ima.save(p, "BMP"))
    add("grey16.png", "exact", lambda p: grey16.save(p, "PNG"))
    add("grey_alpha.png", "exact", lambda p: ima.convert("LA").save(p, "PNG"))


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
        im = ImageOps.exif_transpose(Image.open(path))   # upright, as Canvas
        if im.mode.startswith("I;16") or im.mode == "I":  # 16-bit to 8: / 257
            v = np.asarray(im).astype(np.int64)
            im = Image.fromarray(((v * 255 + 32767) // 65535).astype(np.uint8), "L")
        icc = im.info.get("icc_profile")
        if icc:                                          # in sRGB, as Canvas
            im = ImageCms.profileToProfile(
                im, ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                ImageCms.createProfile("sRGB"), outputMode="RGB",
                renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC)
        ref = np.asarray(im.convert("RGBA")).astype(np.int64)
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
        gaps = {} if len(sys.argv) > 2 else KNOWN_GAPS
        out = os.path.join(d, "out.raw")
        failed = 0
        known = 0
        for path, kind in cases:
            name = os.path.basename(path)
            got, err = canvas_decode(tool, path, out)
            ref = reference_decode(path)
            if err is None and got.shape != ref.shape:
                err = f"size {got.shape[1]}x{got.shape[0]} != {ref.shape[1]}x{ref.shape[0]}"
            if err:
                if name in gaps:
                    print(f"gap   {name:28} {gaps[name]} ({err})")
                    known += 1
                    continue
                print(f"FAIL  {name:28} {err}")
                failed += 1
                continue
            p = psnr(got, ref)
            maxdiff = int(np.max(np.abs(got - ref)))
            ok = p == math.inf if kind == "exact" else p >= LOSSY_PSNR_FLOOR
            if name in gaps:
                if ok:
                    print(f"FAIL  {name:28} passes: remove it from KNOWN_GAPS")
                else:
                    print(f"FAIL  {name:28} decoded wrongly ({p:.2f} dB) "
                          f"instead of refused: {gaps[name]}")
                failed += 1
                continue
            failed += not ok
            shown = "exact" if p == math.inf else f"{p:6.2f} dB"
            print(f"{'ok  ' if ok else 'FAIL'}  {name:28} {shown:>9}  maxdiff={maxdiff}")
        print(f"{len(cases) - failed - known}/{len(cases)} passed, {known} known gaps")
        sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

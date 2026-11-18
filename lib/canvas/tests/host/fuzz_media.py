#!/usr/bin/env python3
"""Fuzz Canvas's image decoders through host_decode (FND-10).

Usage: fuzz_media.py <host_decode binary> [rounds per seed]

A seed of each format image_decode reads is made with Pillow (and an SVG by
hand), then mutated many times with a fixed random seed: bits flipped, bytes
set to edge values, the file cut short, slices repeated or dropped, its
length fields' neighbours scrambled. Each mutant is decoded by host_decode.
Refusing it is fine (exit 3); decoding it is fine. Dying on a signal, or
taking longer than the time limit, fails the run, and the mutant is kept
under the failure's name so it can be made a regression test.

Development-machine test tooling only; not part of any OS image.
"""
import io
import os
import random
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compare_images import make_icc  # noqa: E402

TIME_LIMIT = 10.0           # seconds a decode may take
ROUNDS = 120                # mutants per seed


def png_xmp(xmp):
    """A PNG's iTXt chunk of XMP (XML:com.adobe.xmp), uncompressed."""
    from PIL import PngImagePlugin
    info = PngImagePlugin.PngInfo()
    info.add_itxt("XML:com.adobe.xmp", xmp.decode(), zip=False)
    return info


def seeds():
    """Small valid files, one or more per format, as (name, bytes)."""
    rng = random.Random(7)
    img = Image.new('RGBA', (13, 9))
    img.putdata([(rng.randrange(256), rng.randrange(256), rng.randrange(256),
                  rng.choice((0, 128, 255))) for _ in range(13 * 9)])
    rgb = img.convert('RGB')
    out = []

    def save(name, image, fmt, **kw):
        b = io.BytesIO()
        image.save(b, fmt, **kw)
        out.append((name, b.getvalue()))

    save('rgba.png', img, 'PNG')
    save('palette.png', img.convert('P'), 'PNG')
    save('interlaced.png', rgb, 'PNG', interlace=1)
    save('baseline.jpg', rgb, 'JPEG', quality=80)
    save('sub420.jpg', rgb, 'JPEG', quality=60, subsampling=2)
    save('progressive.jpg', rgb, 'JPEG', quality=70, progressive=True)
    # QA-03: metadata as image_decode reads it (img/meta, color/icc_transform,
    # pixbuf_orient): EXIF orientation, an ICC profile of each curve kind,
    # XMP, in every format that carries them
    exif = Image.Exif()
    exif[0x0112] = 6
    exif = exif.tobytes()
    p3 = [(0.5151, 0.2412, -0.0011), (0.2920, 0.6922, 0.0419), (0.1571, 0.0666, 0.7841)]
    icc_para = make_icc([("para", 3, [2.4, 1 / 1.055, 0.055 / 1.055, 1 / 12.92, 0.04045])] * 3, p3)
    icc_table = make_icc([("table", [i * 4369 for i in range(16)])] * 3, p3)
    icc_gamma = make_icc([("gamma", 1.8)])
    xmp = b'<x:xmpmeta xmlns:x="adobe:ns:meta/"/>'
    save('meta.jpg', rgb, 'JPEG', quality=80, exif=exif, icc_profile=icc_para)
    save('meta.png', rgb, 'PNG', exif=exif, icc_profile=icc_table, pnginfo=png_xmp(xmp))
    save('meta.webp', rgb, 'WEBP', lossless=True, exif=exif, icc_profile=icc_para, xmp=xmp)
    save('meta.tif', rgb, 'TIFF', icc_profile=icc_table)
    save('meta_grey.png', rgb.convert('L'), 'PNG', icc_profile=icc_gamma)
    save('image.pcx', rgb, 'PCX')
    save('palette.pcx', rgb.convert('P'), 'PCX')
    save('palette.tif', rgb.convert('P'), 'TIFF')
    save('rle.tga', rgb.convert('RGBA'), 'TGA', compression='tga_rle')
    save('dxt1.dds', rgb.convert('RGBA'), 'DDS', pixel_format='DXT1')
    save('dxt5.dds', rgb.convert('RGBA'), 'DDS', pixel_format='DXT5')
    save('bc5.dds', rgb, 'DDS', pixel_format='BC5')
    save('progressive_restart.jpg', rgb, 'JPEG', quality=70, progressive=True,
         restart_marker_blocks=2)
    save('anim.gif', img.convert('P'), 'GIF')
    save('rgb.bmp', rgb, 'BMP')
    save('rgba.tga', img, 'TGA')
    save('rgb.ppm', rgb, 'PPM')
    save('lossy.webp', rgb, 'WEBP', quality=70)
    save('lossless.webp', img, 'WEBP', lossless=True)
    save('alpha.webp', img, 'WEBP', quality=70)
    save('rgb.tif', rgb, 'TIFF', compression='tiff_lzw')
    out.append(('shapes.svg', b'<svg xmlns="http://www.w3.org/2000/svg" '
                b'width="16" height="12" viewBox="0 0 16 12">'
                b'<rect x="1" y="1" width="6" height="5" fill="#c33"/>'
                b'<circle cx="11" cy="6" r="4" stroke="#33c" fill="none"/>'
                b'<path d="M1 11 Q8 2 15 11 Z" fill="rgba(0,128,0,0.5)"/>'
                b'</svg>'))
    return out


def mutate(data, rng):
    """One mutant of data: one to four changes."""
    b = bytearray(data)
    for _ in range(rng.randint(1, 4)):
        if not b:
            break
        kind = rng.randrange(6)
        i = rng.randrange(len(b))
        if kind == 0:                                   # a bit flipped
            b[i] ^= 1 << rng.randrange(8)
        elif kind == 1:                                 # an edge value
            b[i] = rng.choice((0, 1, 0x7F, 0x80, 0xFE, 0xFF))
        elif kind == 2:                                 # cut short
            del b[max(1, i):]
        elif kind == 3:                                 # a slice repeated
            j = min(len(b), i + rng.randint(1, 64))
            b[i:i] = b[i:j] * rng.randint(1, 8)
        elif kind == 4:                                 # a slice dropped
            del b[i:i + rng.randint(1, 32)]
        else:                                           # a 32-bit field
            if i + 4 <= len(b):
                v = rng.choice((0, 1, 0x7FFFFFFF, 0x80000000, 0xFFFFFFFF,
                                rng.getrandbits(32)))
                b[i:i + 4] = v.to_bytes(4, rng.choice(('big', 'little')))
    return bytes(b)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    decoder = sys.argv[1]
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else ROUNDS
    rng = random.Random(0xC0FFEE)
    failures = []
    runs = decoded = 0
    tmp = tempfile.mkdtemp(prefix='canvas_fuzz_media_')
    try:
        out = os.path.join(tmp, 'out.raw')
        for name, data in seeds():
            for n in range(rounds + 1):
                mutant = data if n == 0 else mutate(data, rng)
                path = os.path.join(tmp, name)
                with open(path, 'wb') as f:
                    f.write(mutant)
                runs += 1
                try:
                    r = subprocess.run([decoder, path, out],
                                       stdout=subprocess.DEVNULL,
                                       stderr=subprocess.DEVNULL,
                                       timeout=TIME_LIMIT)
                    code = r.returncode
                except subprocess.TimeoutExpired:
                    code = 'timeout'
                if code == 0:
                    decoded += 1
                elif code == 3 or code == 2:
                    pass                                # refused: fine
                else:
                    keep = os.path.join(os.getcwd(),
                                        f'fuzz_media_fail_{n}_{name}')
                    with open(keep, 'wb') as f:
                        f.write(mutant)
                    failures.append(f'{name} mutant {n}: {code}, kept as {keep}')
                if n == 0 and code != 0:
                    failures.append(f'{name}: the seed itself does not decode ({code})')
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for f in failures:
        print('fuzz_media: FAIL', f)
    print(f'fuzz_media: {runs} files, {decoded} decoded, the rest refused, '
          f'{len(failures)} failures')
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Check lib/ufont's Brotli decompression.

Usage: brotli_check.py [host_brotli]

Streams the brotli module makes from varied data - empty, text (the static
dictionary and its transforms), the shipped fonts' tables, random bytes,
long runs, mixed - at every quality and several window sizes, plus
damaged and truncated streams: tools/brotlimodel.py must give back the
data exactly (and refuse damaged ones as the brotli module does); with
host_brotli (sfnt/brotli.asm) its output must equal the model's on all of
them.

Development-machine tooling only; not part of any OS image.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import brotli  # noqa: E402  (the brotli module)
import brotlimodel  # noqa: E402

FONTS = os.path.join(HERE, "..", "..", "fonts")
TEXT = (b"The quick brown fox jumps over the lazy dog. <html><head><title>A page</title></head>"
        b"<body class=\"main\">Some text, with commas; and \"quotes\" - the end.</body></html> "
        b"Les \xc3\xa9l\xc3\xa8ves \xc3\xa9tudient. \xe0\xa4\xa8\xe0\xa4\xae\xe0\xa4\xb8\xe0\xa5\x8d\xe0\xa4\xa4\xe0\xa5\x87 ")


def samples(rng):
    out = [b"", b"a", b"\0" * 1000, TEXT, TEXT * 40, bytes(range(256)) * 9]
    for name in ("NotoSans-Regular.ttf", "NotoSansDevanagari-Regular.ttf", "LiberationMono-Bold.ttf"):
        data = open(os.path.join(FONTS, name), "rb").read()
        for _ in range(3):
            a = rng.randrange(len(data))
            out.append(data[a:a + rng.choice((100, 3000, 40000, 200000))])
    for _ in range(12):
        n = rng.choice((10, 300, 5000, 70000))
        kind = rng.randrange(3)
        if kind == 0:
            out.append(bytes(rng.randrange(256) for _ in range(n)))
        elif kind == 1:
            out.append(bytes(rng.choice(b"abcde \n") for _ in range(n)))
        else:
            words = [TEXT[i:i + rng.randint(2, 12)] for i in range(0, len(TEXT), 7)]
            out.append(b"".join(rng.choice(words) for _ in range(n // 6)))
    return out


def cases(rng):
    out = []
    for data in samples(rng):
        for q in (0, 1, 4, 6, 9, 11):
            for lgwin in (10, 16, 22):
                if q < 4 and lgwin != 22 and len(data) < 1000:
                    continue
                out.append((brotli.compress(data, quality=q, lgwin=lgwin,
                                            mode=rng.choice((brotli.MODE_GENERIC, brotli.MODE_TEXT,
                                                             brotli.MODE_FONT))), data))
    # damaged: bytes changed, truncated
    damaged = []
    for comp, data in out[::5]:
        if len(comp) < 4:
            continue
        b = bytearray(comp)
        for _ in range(rng.choice((1, 3))):
            b[rng.randrange(len(b))] ^= 1 << rng.randrange(8)
        damaged.append(bytes(b))
        damaged.append(comp[:rng.randrange(len(comp))])
    return out, damaged


def reference(comp):
    try:
        return brotli.decompress(comp)
    except brotli.error:
        return None


def run_host(tool, streams, d):
    """host_brotli: u32 n, then (u32 length, bytes) -> per stream i32 length (-1: refused), bytes."""
    inp, outp = os.path.join(d, "in.bin"), os.path.join(d, "out.bin")
    with open(inp, "wb") as f:
        f.write(struct.pack("<I", len(streams)))
        for s in streams:
            f.write(struct.pack("<I", len(s)) + s)
    r = subprocess.run([tool, inp, outp], capture_output=True, timeout=1200)
    if r.returncode:
        return None
    b, at, res = open(outp, "rb").read(), 0, []
    for _ in streams:
        n, = struct.unpack_from("<i", b, at)
        at += 4
        if n < 0:
            res.append(None)
            continue
        res.append(b[at:at + n])
        at += n
    return res


def main():
    tool = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else None
    rng = random.Random(3)
    good, damaged = cases(rng)
    failed = 0
    bad = [i for i, (comp, data) in enumerate(good) if brotlimodel.decompress(comp) != data]
    print(f"{'ok  ' if not bad else 'FAIL'}  model: {len(good) - len(bad)}/{len(good)} streams decoded exactly")
    failed += bool(bad)
    want = [reference(c) for c in damaged]
    got = [brotlimodel.decompress(c) for c in damaged]
    off = sum(1 for g, w in zip(got, want) if g != w)
    print(f"{'ok  ' if not off else 'FAIL'}  model: {len(damaged) - off}/{len(damaged)} damaged streams as the "
          f"brotli module")
    failed += bool(off)
    if tool:
        streams = [c for c, _ in good] + damaged
        model = [d for _, d in good] + got
        with tempfile.TemporaryDirectory(prefix="ufont-brotli.") as d:
            res = run_host(tool, streams, d)
        if res is None:
            print("FAIL  host_brotli crashed")
            failed += 1
        else:
            off = sum(1 for g, w in zip(res, model) if g != w)
            print(f"{'ok  ' if not off else 'FAIL'}  ufont: {len(streams) - off}/{len(streams)} equal to the model")
            failed += bool(off)
    print("failed" if failed else "all passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

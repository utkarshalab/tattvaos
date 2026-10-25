#!/usr/bin/env python3
"""Check lib/ufont against fontTools reading the same fonts.

Usage: font_check.py <host_font> <font directory>

- glyphs: for every shipped font, every code point its cmap maps plus some it
  does not (outside the BMP, unassigned, private use): the glyph ufont_glyph
  finds, its advance, and the outline ufont_outline writes into a ugfx path
  at an uneven size - verbs and points identical to tools/fontmodel.py; then
  all again at another size, the outlines now replayed from the font's
  cache.
- metrics: units per em, ascent and descent.
- matching: ufont_set_face over family lists (generic names, aliases, quoted,
  case, unknown names, none) x weights 100..900 x normal / italic / oblique
  picks the face the model picks.
- damage: truncated fonts and fonts with bytes changed never crash host_font.

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
import fontmodel  # noqa: E402

SIZE = 37.25
SIZE2 = 11.6
VERBS = {'move': (0, 1), 'line': (1, 1), 'quad': (2, 2), 'close': (5, 0)}
EXTRA = [0x10FFFF, 0x1F600, 0x4E00, 0xE000, 0xFFFF, 0x0378, 0x0000, 0x0009]


def run(tool, *args):
    r = subprocess.run([tool, *args], capture_output=True, timeout=300)
    return r.returncode


def path_of(cmds):
    verbs, pts = [], []
    for c in cmds:
        v, n = VERBS[c[0]]
        verbs.append(v)
        pts += list(c[1:1 + 2 * n])
    return verbs, pts


def check_glyphs(tool, d, path, face):
    cps = sorted(face.cmap) + EXTRA
    src = os.path.join(d, "in.bin")
    out = os.path.join(d, "out.bin")
    open(src, "wb").write(struct.pack("<ddI", SIZE, SIZE2, len(cps)) + struct.pack(f"<{len(cps)}I", *cps))
    rc = run(tool, "o", path, src, out)
    if rc:
        return f"exit {rc}"
    b = open(out, "rb").read()
    status, upem, asc, desc = struct.unpack_from("<IIii", b)
    if status or (upem, asc, desc) != (face.upem, face.asc, face.desc):
        return f"metrics {status, upem, asc, desc} want {(0, face.upem, face.asc, face.desc)}"
    at, bad = 16, []
    for size in (SIZE, SIZE2):
        s = size / face.upem
        for cp in cps:
            gid, adv, st, nv, npts = struct.unpack_from("<IIiII", b, at)
            at += 20
            verbs = list(b[at:at + nv])
            at += nv
            pts = list(struct.unpack_from(f"<{2 * npts}d", b, at))
            at += 16 * npts
            wgid = face.glyph(cp)
            wverbs, wpts = path_of(face.outline(wgid, s))
            if (gid, adv, st, verbs, pts) != (wgid, face.advance(wgid), 0, wverbs, wpts):
                bad.append((size, cp))
    return f"{len(bad)} differ, first {bad[0][1]:04X} at size {bad[0][0]}" if bad else None


def check_matching(tool, d, font_dir, fonts):
    families = [None, "", "serif", "sans-serif", "monospace", "Arial", "'Times New Roman', serif",
                '"Courier New"', "NOTO SERIF", "nonesuch", "nonesuch, Cousine", " Liberation Mono , serif",
                "system-ui", "cursive", "Helvetica Neue", "Noto Sans Mono", "Tinos", "ui-monospace", ",,serif",
                "'Arial", "fantasy, monospace"]
    queries = [(f, w, st) for f in families for w in range(100, 1000, 100) for st in (0, 1, 2)]
    blob = struct.pack("<I", len(queries))
    for f, w, st in queries:
        fb = None if f is None else f.encode()
        blob += struct.pack("<III", w, st, 0xFFFFFFFF if fb is None else len(fb)) + (fb or b"")
    src, out = os.path.join(d, "q.bin"), os.path.join(d, "a.bin")
    open(src, "wb").write(blob)
    rc = run(tool, "m", font_dir, src, out)
    if rc:
        return f"exit {rc}", len(queries)
    got = struct.unpack(f"<{len(queries)}i", open(out, "rb").read())
    bad = [(q, g, fonts.face(*q).std) for q, g in zip(queries, got) if g != fonts.face(*q).std]
    return (f"{len(bad)} differ, first {bad[0]}" if bad else None), len(queries)


def main():
    tool, font_dir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    fonts = fontmodel.FontSet(font_dir)
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ufont.") as d:
        for name, _, _, _ in fontmodel.STANDARD:
            path = os.path.join(font_dir, name)
            face = next(f for f in fonts.faces if f.std == [s[0] for s in fontmodel.STANDARD].index(name))
            err = check_glyphs(tool, d, path, face)
            total += 1
            failed += err is not None
            print(f"{'ok  ' if err is None else 'FAIL'}  glyphs {name:32} {len(face.cmap):5} mapped"
                  + (f"  {err}" if err else ""))
        err, n = check_matching(tool, d, font_dir, fonts)
        total += 1
        failed += err is not None
        print(f"{'ok  ' if err is None else 'FAIL'}  matching {n} queries" + (f"  {err}" if err else ""))
        rng = random.Random(11)
        cps = list(range(32, 0x250)) + list(range(0x370, 0x530))
        src = os.path.join(d, "in.bin")
        open(src, "wb").write(struct.pack("<ddI", SIZE, SIZE2, len(cps)) + struct.pack(f"<{len(cps)}I", *cps))
        crashes = runs = 0
        for name in ("NotoSans-Regular.ttf", "NotoSerif-Bold.ttf", "LiberationSans-Italic.ttf"):
            data = open(os.path.join(font_dir, name), "rb").read()
            variants = [data[:n] for n in (0, 11, 12, 13, 64, 300, 2000, len(data) // 2, len(data) - 1)]
            for _ in range(60):
                b = bytearray(data)
                for _ in range(rng.choice((1, 3, 16, 128))):
                    b[rng.randrange(len(b))] = rng.randrange(256)
                variants.append(bytes(b))
            for v in variants:
                p = os.path.join(d, "damaged.ttf")
                open(p, "wb").write(v)
                rc = run(tool, "o", p, src, os.path.join(d, "out.bin"))
                runs += 1
                crashes += rc not in (0, 2)
        total += 1
        failed += crashes > 0
        print(f"{'ok  ' if not crashes else 'FAIL'}  damaged fonts {runs} runs, {crashes} crashed")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

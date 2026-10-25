#!/usr/bin/env python3
"""Check lib/ufont's shaping (ufont_shape) against tools/shapemodel.py.

Usage: shape_check.py <host_shape> <font directory> [cases per font]

For every shipped font: words in Latin, Greek, Cyrillic and Devanagari,
then random strings - characters the font maps mixed with combining marks,
joiners, spaces, ligature letters and default ignorables, and random
Devanagari syllables (consonant clusters, reph, nukta, matras, signs, broken
clusters). Every glyph, cluster, advance and offset ufont_shape gives must
equal the model's. Noto Sans Devanagari altered four ways (only the old
'deva' script, only DFLT, no GSUB, no GDEF) takes the shaper down its other
paths. When uharfbuzz is installed the model is also compared with
HarfBuzz on the same cases (the model is meant to be HarfBuzz step for
step). Truncated and corrupted fonts must not crash host_shape.

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
import shapemodel as sm  # noqa: E402

try:
    import uharfbuzz as hb
except ImportError:
    hb = None

WORDS = """office affluent fjord Waffle AVATAR Tyre VAT LT P. "quoted" naïve café Ångström
résumé coöperate Zürich œuvre ĳssel Ǆemal ǅ ǉ ﬁ ﬂ ﬀi á ẹ̀ ȫ i̇́
q̣̇ Ω ἀρχή Ἄλφα ᾅ ά ΐ Москва ёлка й Ӂ ї ґ щ ъ 1⁄2 x12⁄345y 3⁄ a‍b
a‌b a͏́ ­ soft­hyphen a b a b a b 　 a️b
नमस्ते हिन्दी संस्कृत कृष्ण धर्म सूर्य पूर्ण वर्ष क्षत्रिय ज्ञान श्री द्ध ह्म कि की कु के कै को कौ कं कः कँ
क़ ज़ ड़ ऩ ऱ ऴ स्त्री र्त्स्न्य र्कि विद्यार्थी प्रार्थना अं अः ॐ ऽ । ० १ २ क्‍ष क्‌ष र्‍य ं ा ि ्
अा अॆ आॅ उु एॅ र्इ क॒ क᳚ ꣠ क꣠ ᳩ राष्ट्र शृङ्गार कार्त्स्न्य Hello नमस्ते 123""".split()

CONS = list(range(0x0915, 0x093A)) + list(range(0x0958, 0x0960)) + list(range(0x0978, 0x0980))
MATRA = list(range(0x093E, 0x094D)) + [0x093A, 0x093B, 0x094E, 0x094F, 0x0955, 0x0956, 0x0957, 0x0962, 0x0963]
VOW = list(range(0x0904, 0x0915)) + [0x0960, 0x0961] + list(range(0x0972, 0x0978))
SIGNS = [0x0900, 0x0901, 0x0902, 0x0903, 0x093C, 0x0951, 0x0952, 0x0953, 0x0954, 0x093D, 0x0950, 0x0964, 0x1CD0,
         0x1CE9, 0xA8E0, 0xA8F2, 0xA8FB, 0x1CF2]


def devanagari(rng):
    out = []
    for _ in range(rng.randint(1, 4)):
        r = rng.random()
        if r < 0.75:
            if rng.random() < 0.25:
                out += [0x0930, 0x094D]
            for k in range(rng.choice((1, 1, 2, 2, 3))):
                if k:
                    out.append(0x094D)
                    if rng.random() < 0.12:
                        out.append(rng.choice((0x200C, 0x200D)))
                out.append(rng.choice(CONS))
                if rng.random() < 0.15:
                    out.append(0x093C)
            if rng.random() < 0.7:
                out.append(rng.choice(MATRA))
            if rng.random() < 0.15:
                out.append(0x094D)
            if rng.random() < 0.3:
                out.append(rng.choice(SIGNS))
        elif r < 0.85:
            out.append(rng.choice(VOW))
            if rng.random() < 0.4:
                out.append(rng.choice(MATRA + SIGNS))
        elif r < 0.95:
            out.append(rng.choice(MATRA + SIGNS + [0x094D, 0x200C, 0x200D, 0x25CC, 0x00A0]))
        else:
            out.append(rng.choice((0x20, 0x41, 0x2D, 0x31)))
    return out


def general(rng, cmap, marks):
    special = [ord(x) for x in "fiflAVTWYLPoaeyv.,-'\"ffi"] + [0x200D, 0x200C, 0xAD, 0x20, 0xA0, 0x2009, 0x2011,
                                                                 0x034F, 0xFE0F, 0x2044, 0x31, 0x32]
    cps = []
    for _ in range(rng.randint(1, 18)):
        r = rng.random()
        if r < 0.3:
            cps.append(rng.choice(marks))
        elif r < 0.55:
            cps.append(rng.choice(special))
        else:
            cps.append(rng.choice(cmap))
    return cps


def run(tool, font, cases, d):
    src, out = os.path.join(d, "in.bin"), os.path.join(d, "out.bin")
    blob = struct.pack("<I", len(cases))
    for cps in cases:
        blob += struct.pack("<III", 0, 0, len(cps)) + struct.pack(f"<{len(cps)}I", *cps)
    open(src, "wb").write(blob)
    r = subprocess.run([tool, font, src, out], capture_output=True, timeout=600)
    if r.returncode:
        return r.returncode, None
    b = open(out, "rb").read()
    status, = struct.unpack_from("<I", b)
    at, res = 4, []
    for _ in cases:
        n, = struct.unpack_from("<I", b, at)
        at += 4
        if n == 0xFFFFFFFF:
            res.append(None)
            continue
        recs = [struct.unpack_from("<IIiiii", b, at + 24 * k) for k in range(n)]
        at += 24 * n
        res.append(recs)
    return status, res


def harfbuzz(path, cases):
    face = hb.Face(hb.Blob.from_file_path(path))
    font = hb.Font(face)
    out = []
    for cps in cases:
        buf = hb.Buffer()
        buf.add_codepoints(cps)
        buf.guess_segment_properties()
        hb.shape(font, buf, {})
        out.append([(i.codepoint, i.cluster, p.x_advance, p.y_advance, p.x_offset, p.y_offset)
                    for i, p in zip(buf.glyph_infos, buf.glyph_positions)])
    return out


def altered(font_dir, d):
    """Noto Sans Devanagari made old-spec only, DFLT only, without GSUB, without GDEF."""
    from fontTools.ttLib import TTFont
    src = os.path.join(font_dir, "NotoSansDevanagari-Regular.ttf")
    out = []
    if not os.path.exists(src):
        return out
    for kind in ("old-spec", "DFLT-only", "no-GSUB", "no-GDEF"):
        f = TTFont(src)
        if kind in ("old-spec", "DFLT-only"):
            drop = ("dev2",) if kind == "old-spec" else ("dev2", "deva")
            for t in ("GSUB", "GPOS"):
                sl = f[t].table.ScriptList
                sl.ScriptRecord = [r for r in sl.ScriptRecord if r.ScriptTag not in drop]
                sl.ScriptCount = len(sl.ScriptRecord)
        else:
            del f["GSUB" if kind == "no-GSUB" else "GDEF"]
        path = os.path.join(d, f"{kind}.ttf")
        f.save(path)
        out.append(path)
    return out


def check_font(tool, path, name, cases, d):
    font = sm.Font(path)
    status, got = run(tool, path, cases, d)
    want = [sm.shape(font, cps, script=sm.guess_script(cps)) for cps in cases]
    if got is None:
        bad = [f"host_shape exit {status}"]
    else:
        bad = [(cps, g, w) for cps, g, w in zip(cases, got, want) if (g and [tuple(x) for x in g]) != w]
    note = ""
    if hb is not None:
        hbres = harfbuzz(path, cases)
        off = sum(1 for w, h in zip(want, hbres) if w != h)
        note = f"  model vs HarfBuzz: {len(cases) - off}/{len(cases)}"
    print(f"{'ok  ' if not bad else 'FAIL'}  {name:34} {len(cases) - len(bad)}/{len(cases)}{note}")
    for item in bad[:3]:
        if isinstance(item, str):
            print("      ", item)
            continue
        cps, g, w = item
        print("      ", " ".join(f"{c:04X}" for c in cps))
        print("       ufont", g)
        print("       model", w)
    return not bad


def damage(tool, font_dir, d, rng):
    """Truncated and corrupted fonts: host_shape may refuse them, never crash."""
    cases = [[ord(c) for c in w] for w in WORDS[:60]]
    runs = crashes = 0
    for name in ("NotoSans-Regular.ttf", "NotoSansDevanagari-Regular.ttf", "LiberationSerif-Italic.ttf"):
        data = open(os.path.join(font_dir, name), "rb").read()
        variants = [data[:n] for n in (12, 300, 4000, len(data) // 3, len(data) - 1)]
        for _ in range(50):
            b = bytearray(data)
            for _ in range(rng.choice((1, 4, 32, 256))):
                b[rng.randrange(len(b))] = rng.randrange(256)
            variants.append(bytes(b))
        for v in variants:
            p = os.path.join(d, "damaged.ttf")
            open(p, "wb").write(v)
            src, out = os.path.join(d, "in.bin"), os.path.join(d, "out.bin")
            blob = struct.pack("<I", len(cases))
            for cps in cases:
                blob += struct.pack("<III", 0, 0, len(cps)) + struct.pack(f"<{len(cps)}I", *cps)
            open(src, "wb").write(blob)
            r = subprocess.run([tool, p, src, out], capture_output=True, timeout=600)
            runs += 1
            crashes += r.returncode != 0
    return runs, crashes


def main():
    tool, font_dir = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
    per_font = int(sys.argv[3]) if len(sys.argv) > 3 else 300
    rng = random.Random(23)
    failed = total = 0
    with tempfile.TemporaryDirectory(prefix="ufont-shape.") as d:
        for name in sorted(f for f in os.listdir(font_dir) if f.endswith(".ttf")):
            path = os.path.join(font_dir, name)
            font = sm.Font(path)
            rtl = lambda c: 0x0590 <= c <= 0x08FF or 0xFB1D <= c <= 0xFDFF or 0xFE70 <= c <= 0xFEFF  # noqa: E731
            cmap = sorted(c for c in font.cmap if not rtl(c))
            marks = [c for c in cmap if sm.is_mark_gc(sm.gc(c))] + [0x0301, 0x0308, 0x0323, 0x0327, 0x0345]
            cases = [[ord(c) for c in w] for w in WORDS]
            for _ in range(per_font):
                cases.append(devanagari(rng) if "Devanagari" in name or rng.random() < 0.2
                             else general(rng, cmap, marks))
            total += 1
            failed += not check_font(tool, path, name, cases, d)
        for path in altered(font_dir, d):
            cases = [[ord(c) for c in w] for w in WORDS] + [devanagari(rng) for _ in range(per_font)]
            total += 1
            failed += not check_font(tool, path, "NotoSansDevanagari " + os.path.basename(path)[:-4], cases, d)
        runs, crashes = damage(tool, font_dir, d, rng)
        total += 1
        failed += crashes > 0
        print(f"{'ok  ' if not crashes else 'FAIL'}  damaged fonts {runs} runs, {crashes} crashed")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

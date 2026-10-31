#!/usr/bin/env python3
"""Check lib/ufont's shaping (ufont_shape) against tools/shapemodel.py.

Usage: shape_check.py <host_shape> <font directory> [cases per font]

For every shipped font: words in Latin, Greek, Cyrillic, the Indic
scripts, Arabic and Hebrew, then random strings - characters the font maps
mixed with combining marks, joiners, spaces, ligature letters and default
ignorables; random syllables in the font's Indic script (consonant
clusters, reph, nukta, matras, signs, joiners, broken clusters); random
Arabic or Hebrew (letters, harakat and points, modifier marks, tatweel,
joiners, digits, mirrored brackets) for those fonts, shaped right to
left; Thai, Lao, Korean, Khmer, Myanmar and the other test fonts'
scripts (tests/fonts), Noto Sans Thai made an old PUA font (no thai
GSUB) and Noto Sans Myanmar retagged mymr. Every glyph, cluster, advance
and offset ufont_shape gives must equal the model's. Noto Sans Devanagari altered four ways (only the old
'deva' script, only DFLT, no GSUB, no GDEF) takes the shaper down its other
paths; Noto Sans, Noto Sans Arabic, Noto Sans Hebrew and Noto Sans
Devanagari without GPOS, GSUB or GDEF (or all three) take the fallbacks -
marks placed by combining class, Arabic forms and ligatures from
presentation forms, the kern table. Some cases are shaped in a direction asked for (as bidi runs are),
left to right or right to left against their script. When uharfbuzz is installed the model is also compared with
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
from indic_data import TABLE  # noqa: E402

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


INDIC_BLOCKS = {'Bengali': 0x0980, 'Gurmukhi': 0x0A00, 'Gujarati': 0x0A80, 'Oriya': 0x0B00, 'Tamil': 0x0B80,
                'Telugu': 0x0C00, 'Kannada': 0x0C80, 'Malayalam': 0x0D00}
INDIC_WORDS = '''বাংলা ভাষা কর্ম সূর্য্য ক্ষ জ্ঞ র‍্যাব কি কো কৌ র্কি শ্রী ਪੰਜਾਬੀ ਗੁਰਮੁਖੀ ਕਿ ਸ੍ਵ ਪ੍ਰ ਖ਼ ਕੌ
ગુજરાતી ભાષા કર્મ ક્ષ જ્ઞ કિ ર્કિ શ્રી ଓଡ଼ିଆ ଭାଷା କର୍ମ କ୍ଷ କି କୋ ର୍କି தமிழ் மொழி கொ கோ கௌ க்ஷ ஸ்ரீ
తెలుగు భాష కర్మ క్ష కి కొ కౌ ర్కి శ్రీ ర‍్క ಕನ್ನಡ ಭಾಷೆ ಕರ್ಮ ಕ್ಷ ಕಿ ಕೊ ರ್ಕಿ ಶ್ರೀ ರ್‍ಕ ರ‍್ಕ
മലയാളം ഭാഷ കർമ്മ ക്ഷ കി കൊ കൌ ർക്ക ശ്രീ ന്റെ പ̇ െപ̇'''.split()


def indic(rng, base):
    """Random syllables of the Indic script whose block starts at base."""
    p = {}
    for u in range(base, base + 0x80):
        p.setdefault(TABLE.get(u, (0, 14))[0], []).append(u)
    virama = (p.get(4) or [base + 0x4D])[0]
    cons, vow = p.get(1, []) + p.get(15, []), p.get(2, [])
    matra = p.get(7, []) + p.get(13, [])
    signs = p.get(8, []) + p.get(9, []) + p.get(3, []) + p.get(57, [])
    out = []
    for _ in range(rng.randint(1, 4)):
        r = rng.random()
        if r < 0.75 and cons:
            if rng.random() < 0.2 and p.get(15):
                out += [p[15][0], virama]
                if rng.random() < 0.2:
                    out.append(0x200D)
            for k in range(rng.choice((1, 1, 2, 2, 3))):
                if k:
                    out.append(virama)
                    if rng.random() < 0.15:
                        out.append(rng.choice((0x200C, 0x200D)))
                out.append(rng.choice(cons))
                if rng.random() < 0.1 and p.get(3):
                    out.append(rng.choice(p[3]))
            if rng.random() < 0.7 and matra:
                out.append(rng.choice(matra))
            if rng.random() < 0.15:
                out.append(virama)
            if rng.random() < 0.3 and signs:
                out.append(rng.choice(signs))
        elif r < 0.85 and vow:
            out.append(rng.choice(vow))
            if rng.random() < 0.5 and (matra or signs):
                out.append(rng.choice(matra + signs))
        elif r < 0.95:
            out.append(rng.choice(matra + signs + [virama, 0x200C, 0x200D, 0x25CC]))
        else:
            out.append(rng.choice((0x20, 0x41, 0x2D)))
    return out


RTL_WORDS = '''العربية مرحبا بالعالم لا لأ لإ لآ الله محمد قُرْآن كِتَابٌ مـــد (نص) [قوس] ١٢٣
بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ سلام‌دنیا فارسی گچپژ اردو ٹڈڑ ه‍ ‍ه‍ ‍ه ئٔ آٓ
שלום עולם עִבְרִית בְּרֵאשִׁית שָׁלוֹם (סוגריים) אָ בַּ שׁ שׂ וּ יִ ײַ אַ כֿ פֿ'''.split()


def rtl_text(rng, arabic):
    """Random Arabic or Hebrew."""
    if arabic:
        letters = list(range(0x0621, 0x063B)) + list(range(0x0641, 0x064B)) + [0x0671, 0x067E, 0x0686, 0x0698,
                                                                              0x06A9, 0x06AF, 0x06CC, 0x06D2]
        marks = list(range(0x064B, 0x0660)) + [0x0670, 0x06D6, 0x06DC, 0x06E3, 0x06E7, 0x06E8]
        other = [0x0640, 0x200C, 0x200D, 0x20, 0x28, 0x29, 0x5B, 0x5D, 0x0660, 0x0661, 0x31, 0x2E, 0x060C, 0x061F]
    else:
        letters = list(range(0x05D0, 0x05EB)) + [0x05F0, 0x05F1, 0x05F2]
        marks = list(range(0x05B0, 0x05BE)) + [0x05BF, 0x05C1, 0x05C2, 0x05C4, 0x05C5, 0x05C7, 0x0591, 0x0596, 0x05A5]
        other = [0x20, 0x28, 0x29, 0x05BE, 0x05F3, 0x31, 0x2E, 0x200D, 0x200C]
    out = []
    for _ in range(rng.randint(1, 14)):
        r = rng.random()
        out.append(rng.choice(letters if r < 0.6 else marks if r < 0.85 else other))
    return out


def _pick(rng, groups, most=14):
    """Up to most characters, each from one of (weight, characters) groups."""
    out = []
    for _ in range(rng.randint(1, most)):
        r, acc = rng.random(), 0
        for w, g in groups:
            acc += w
            if r < acc:
                break
        out.append(rng.choice(g))
    return out


def thai(rng):
    """Random Thai: consonants, SARA AM, vowels, above marks and tone marks, leading vowels, digits."""
    return _pick(rng, [(0.45, list(range(0x0E01, 0x0E2F))), (0.15, [0x0E33] * 3 + list(range(0x0E30, 0x0E3B))),
                       (0.25, list(range(0x0E47, 0x0E4F)) + [0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37]),
                       (0.1, list(range(0x0E40, 0x0E46)) + list(range(0x0E50, 0x0E5C))),
                       (0.05, [0x20, 0x200B, 0x200D, 0x25CC, 0x31])])


def lao(rng):
    """Random Lao: Thai's shapes moved to the Lao block."""
    return [c + 0x80 if 0x0E00 <= c < 0x0E80 else c for c in thai(rng)]


def hangul(rng):
    """Random Korean: <L,V(,T)> jamo (modern and old), syllables (some the font lacks, LV ones
    followed by trailing jamo), tone marks, stray jamo."""
    lead = list(range(0x1100, 0x1113)) + list(range(0x1113, 0x1160, 7)) + list(range(0xA960, 0xA97D, 5))
    vowel = list(range(0x1161, 0x1176)) + list(range(0x1176, 0x11A8, 6)) + list(range(0xD7B0, 0xD7C7, 5))
    trail = list(range(0x11A8, 0x11C3)) + list(range(0x11C3, 0x1200, 8)) + list(range(0xD7CB, 0xD7FC, 7))
    out = []
    for _ in range(rng.randint(1, 8)):
        r = rng.random()
        if r < 0.35:
            out += [rng.choice(lead), rng.choice(vowel)] + ([rng.choice(trail)] if rng.random() < 0.5 else [])
        elif r < 0.65:
            k = rng.random()
            out.append(0xAC00 + (rng.randrange(11172) if k < 0.4 else rng.randrange(1764) if k < 0.8
                                 else 28 * rng.randrange(399)))
            if rng.random() < 0.4:
                out.append(rng.choice(trail))
        elif r < 0.75:
            out.append(rng.choice((0x302E, 0x302F)))
        elif r < 0.9:
            out.append(rng.choice(lead + vowel + trail))
        else:
            out.append(rng.choice((0x20, 0x41, 0x25CC, 0x0301, 0x200D, 0x3131)))
    return out


def khmer(rng):
    """Random Khmer syllables: consonants (robat and the like after some), coeng + consonant or RO
    (two or three of them), split and pre-base vowels, signs, joiners; and broken clusters."""
    cons = list(range(0x1780, 0x17A3))
    out = []
    for _ in range(rng.randint(1, 5)):
        r = rng.random()
        if r < 0.75:
            out.append(rng.choice(cons))
            if rng.random() < 0.15:
                if rng.random() < 0.3:
                    out.append(rng.choice((0x200C, 0x200D)))
                out.append(rng.choice((0x17C9, 0x17CA, 0x17CC)))
            for _ in range(rng.choice((0, 0, 1, 1, 2, 3))):
                out += [0x17D2, rng.choice(cons + [0x179A] * 6 + list(range(0x17A3, 0x17B4)))]
            for _ in range(rng.choice((0, 1, 1, 2))):
                out.append(rng.choice(list(range(0x17B6, 0x17C6)) + [0x17C1, 0x17C2, 0x17C3] * 2))
            for _ in range(rng.choice((0, 0, 1, 2))):
                out.append(rng.choice(list(range(0x17C6, 0x17D2)) + [0x17D3, 0x17DD, 0x200C, 0x200D]))
        elif r < 0.85:
            out.append(rng.choice(list(range(0x17A3, 0x17B4)) + [0x25CC, 0x17D9, 0x00A0]))
        else:
            out.append(rng.choice(list(range(0x17B6, 0x17D4)) + [0x17D2, 0x20, 0x17E0, 0x17D4]))
    return out


def myanmar(rng):
    """Random Myanmar syllables: kinzi, consonants (Mon, Shan and others), variation selectors,
    stacked consonants, medials, vowels (pre-base ones repeated), tones, asat, joiners."""
    cons = list(range(0x1000, 0x1021)) + [0x103F, 0x104E] + list(range(0x1050, 0x1056)) +         list(range(0x105A, 0x105E))
    medials = (0x103B, 0x103C, 0x103D, 0x103E, 0x105E, 0x105F, 0x1060, 0x1082, 0x103A)
    vowels = list(range(0x102B, 0x1036)) + [0x1031] * 3 + [0x1084, 0x1056, 0x1057, 0x1062, 0x1067]
    tones = (0x1036, 0x1037, 0x1038, 0x103A, 0x1032, 0x1087, 0x1089, 0x108F, 0x1063, 0x109A, 0x200C, 0x200D)
    out = []
    for _ in range(rng.randint(1, 4)):
        if rng.random() < 0.8:
            if rng.random() < 0.1:
                out += [0x1004, 0x103A, 0x1039]
            out.append(rng.choice(cons + [0x1021, 0x1023, 0x1025, 0x1027, 0x25CC]))
            if rng.random() < 0.1:
                out.append(rng.choice((0xFE00, 0xFE01)))
            for _ in range(rng.choice((0, 0, 0, 1, 2))):
                out += [0x1039, rng.choice(cons)]
            out += [rng.choice(medials) for _ in range(rng.choice((0, 1, 1, 2)))]
            out += [rng.choice(vowels) for _ in range(rng.choice((0, 1, 1, 2, 3)))]
            out += [rng.choice(tones) for _ in range(rng.choice((0, 1, 1, 2)))]
        else:
            out.append(rng.choice(list(range(0x102B, 0x1040)) + [0x104A, 0x104B, 0x20, 0x1040, 0x1041, 0xA9E5,
                                                                  0xAA7B]))
    return out


# the test fonts' scripts (tests/fonts/<name>-Regular.ttf / .otf): the text they are shaped with
SCRIPT_TEXT = {'Thai': thai, 'Lao': lao, 'KR': hangul, 'Khmer': khmer, 'Myanmar': myanmar}
SCRIPT_WORDS = """สวัสดี ภาษาไทย น้ำ ทำ กำลัง ปั้ม ฟ้า ญู ฐู ปิ่น ป่า ฎุ ญุ ปั่น ก่ำ ก้ำ ดํ่า ไก่ เป็น
ສະບາຍດີ ພາສາລາວ ນ້ຳ ທຳ ກຳລັງ ປັ້ນ ຫຼວງ ເປັນ 한국어 안녕하세요 한글 〮한 ᄒᆞᆫ 〯ᄀᆞ
ភាសាខ្មែរ ស្រី ក្រុង ព្រះ ខ្ញុំ សួស្តី កើត ស្ត្រី
မြန်မာဘာသာ မင်္ဂလာပါ သင်္ချိုင်း ကျွန်ုပ် ပြည်ထောင်စု""".split()


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


VARIATIONS = {}                         # the axes host_shape sets (variable fonts)


def split(case):
    """A case: code points, or (code points, 'ltr' / 'rtl') shaped in that direction."""
    return (case, None) if isinstance(case, list) else case


def run(tool, font, cases, d):
    src, out = os.path.join(d, "in.bin"), os.path.join(d, "out.bin")
    blob = struct.pack("<I", len(VARIATIONS)) + b"".join(
        struct.pack("<4sf", t.encode(), v) for t, v in VARIATIONS.items())
    blob += struct.pack("<I", len(cases))
    for case in cases:
        cps, direction = split(case)
        blob += struct.pack("<IIII", 0, 0, {None: 0, "ltr": 1, "rtl": 2}[direction], len(cps))
        blob += struct.pack(f"<{len(cps)}I", *cps)
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
    if VARIATIONS:
        font.set_variations(VARIATIONS)
    out = []
    for case in cases:
        cps, direction = split(case)
        buf = hb.Buffer()
        buf.add_codepoints(cps)
        if direction:
            buf.direction = direction
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


def stripped(font_dir, d):
    """Fonts without their layout tables (positioning by fallback, Arabic fallback shaping from
    presentation forms, the kern table): Noto Sans, Noto Sans Arabic and Noto Sans Hebrew without
    GPOS, GSUB, GDEF or all three; Noto Sans Devanagari without GPOS or all three."""
    from fontTools.ttLib import TTFont
    out = []
    for name, kinds in (("NotoSans-Regular.ttf", ("GPOS", "GSUB", "GDEF", "all")),
                        ("NotoSansArabic-Regular.ttf", ("GPOS", "GSUB", "GDEF", "all")),
                        ("NotoSansHebrew-Regular.ttf", ("GPOS", "GSUB", "GDEF", "all")),
                        ("NotoSansDevanagari-Regular.ttf", ("GPOS", "all"))):
        src = os.path.join(font_dir, name)
        if not os.path.exists(src):
            continue
        for kind in kinds:
            f = TTFont(src)
            for t in (("GPOS", "GSUB", "GDEF") if kind == "all" else (kind,)):
                if t in f:
                    del f[t]
            path = os.path.join(d, name.replace("-Regular.ttf", f"-no-{kind}.ttf"))
            f.save(path)
            out.append(path)
    return out


def thai_pua(d):
    """Noto Sans Thai as an old Thai font: no thai GSUB script, PUA glyphs (Windows' code points
    for some characters, the Mac's for the others)."""
    from fontTools.ttLib import TTFont
    from thai import PUA
    src = os.path.join(HERE, "..", "fonts", "NotoSansThai-Regular.ttf")
    if not os.path.exists(src):
        return []
    f = TTFont(src)
    order = f.getGlyphOrder()
    k = 0
    for t in f["cmap"].tables:
        if t.isUnicode():
            for rows in PUA.values():
                for i, (_, win, mac) in enumerate(rows):
                    t.cmap[win if i % 3 else mac] = order[10 + k % 40]
                    k += 1
    sl = f["GSUB"].table.ScriptList
    sl.ScriptRecord = [r for r in sl.ScriptRecord if r.ScriptTag != "thai"]
    sl.ScriptCount = len(sl.ScriptRecord)
    path = os.path.join(d, "NotoSansThai-PUA.ttf")
    f.save(path)
    return [path]


def myanmar_old(d):
    """Noto Sans Myanmar with its mym2 script tagged the old mymr (the default shaper then)."""
    from fontTools.ttLib import TTFont
    src = os.path.join(HERE, "..", "fonts", "NotoSansMyanmar-Regular.ttf")
    if not os.path.exists(src):
        return []
    f = TTFont(src)
    for t in ("GSUB", "GPOS"):
        for r in f[t].table.ScriptList.ScriptRecord:
            if r.ScriptTag == "mym2":
                r.ScriptTag = "mymr"
    path = os.path.join(d, "NotoSansMyanmar-mymr.ttf")
    f.save(path)
    return [path]


def check_font(tool, path, name, cases, d):
    font = sm.Font(path)
    if VARIATIONS:
        font.set_variations(VARIATIONS)
    status, got = run(tool, path, cases, d)
    want = [sm.shape(font, cps, script=sm.guess_script(cps), direction=dr) for cps, dr in map(split, cases)]
    if got is None:
        bad = [f"host_shape exit {status}"]
    else:
        bad = [(split(c)[0], g, w) for c, g, w in zip(cases, got, want) if (g and [tuple(x) for x in g]) != w]
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
            blob = struct.pack("<II", 0, len(cases))                 # no axes set
            for cps in cases:
                blob += struct.pack("<IIII", 0, 0, 0, len(cps)) + struct.pack(f"<{len(cps)}I", *cps)
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
            cmap = sorted(font.cmap)
            marks = [c for c in cmap if sm.is_mark_gc(sm.gc(c))] + [0x0301, 0x0308, 0x0323, 0x0327, 0x0345]
            cases = [[ord(c) for c in w] for w in WORDS + INDIC_WORDS + RTL_WORDS]
            script = next((k for k in INDIC_BLOCKS if k in name), None)
            for _ in range(per_font):
                if "Arabic" in name or "Hebrew" in name:
                    cases.append(rtl_text(rng, "Arabic" in name))
                elif script:
                    cases.append(indic(rng, INDIC_BLOCKS[script]))
                elif "Devanagari" in name or rng.random() < 0.2:
                    cases.append(devanagari(rng))
                else:
                    cases.append(general(rng, cmap, marks))
            # some shaped in a direction asked for (a bidi run's), with brackets and digits
            common = [0x28, 0x29, 0x5B, 0x5D, 0x31, 0x32, 0x20, 0x2E, 0x2044, 0x0660, 0x0661, 0x1F1EE, 0x1F1F3]
            plain = list(cases)
            for _ in range(per_font // 5):
                cps = list(rng.choice(plain)) if rng.random() < 0.7 else []
                cps += [rng.choice(common) for _ in range(rng.randint(0 if cps else 1, 4))]
                cases.append((cps, rng.choice(("ltr", "rtl"))))
            total += 1
            failed += not check_font(tool, path, name, cases, d)
        # the test fonts of other scripts, and an old (PUA) Thai font
        test_fonts = os.path.join(HERE, "..", "fonts")
        script_fonts = [os.path.join(test_fonts, f) for f in sorted(os.listdir(test_fonts))
                        if f.endswith(("-Regular.ttf", "-Regular.otf"))]
        for path in script_fonts + thai_pua(d) + myanmar_old(d):
            name = os.path.basename(path)[:-4]
            gen = next((g for k, g in SCRIPT_TEXT.items() if k in name), None)
            if gen is None:
                continue
            cases = [[ord(c) for c in w] for w in SCRIPT_WORDS + WORDS[:40]]
            cases += [gen(rng) for _ in range(per_font * 2)]
            total += 1
            failed += not check_font(tool, path, name, cases, d)
        for path in altered(font_dir, d):
            cases = [[ord(c) for c in w] for w in WORDS] + [devanagari(rng) for _ in range(per_font)]
            total += 1
            failed += not check_font(tool, path, "NotoSansDevanagari " + os.path.basename(path)[:-4], cases, d)
        for path in stripped(font_dir, d):
            name = os.path.basename(path)
            font = sm.Font(path)
            cmap = sorted(font.cmap)
            marks = [c for c in cmap if sm.is_mark_gc(sm.gc(c))] + [0x0301, 0x0308, 0x0323, 0x0327, 0x0345]
            cases = [[ord(c) for c in w] for w in WORDS + RTL_WORDS]
            for _ in range(per_font):
                if "Arabic" in name or "Hebrew" in name:
                    cases.append(rtl_text(rng, "Arabic" in name))
                elif "Devanagari" in name:
                    cases.append(devanagari(rng))
                else:
                    cases.append(general(rng, cmap, marks))
            total += 1
            failed += not check_font(tool, path, name[:-4], cases, d)
        runs, crashes = damage(tool, font_dir, d, rng)
        total += 1
        failed += crashes > 0
        print(f"{'ok  ' if not crashes else 'FAIL'}  damaged fonts {runs} runs, {crashes} crashed")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

"""HarfBuzz's Hangul shaper (hb-ot-shaper-hangul.cc), for shapemodel.py.

A syllable is precomposed when the font has the precomposed glyph (<L,V>, <L,V,T>, <LV,T>),
otherwise decomposed into jamo (when the font has them) that get the ljmo / vjmo / tjmo features;
a tone mark after a syllable moves in front of it unless its glyph is zero-width, and one with no
syllable before it gets a dotted circle. No normalization beyond the short circuit, calt off, no
mark zeroing. Development-machine tooling only.
"""
L_BASE, V_BASE, T_BASE, S_BASE = 0x1100, 0x1161, 0x11A7, 0xAC00
L_COUNT, V_COUNT, T_COUNT = 19, 21, 28
N_COUNT = V_COUNT * T_COUNT
S_COUNT = L_COUNT * N_COUNT
LJMO, VJMO, TJMO = 1, 2, 3
FEATURES = (None, 'ljmo', 'vjmo', 'tjmo')


def is_combining_l(u):
    return L_BASE <= u < L_BASE + L_COUNT


def is_combining_v(u):
    return V_BASE <= u < V_BASE + V_COUNT


def is_combining_t(u):
    return T_BASE + 1 <= u < T_BASE + T_COUNT


def is_combined_s(u):
    return S_BASE <= u < S_BASE + S_COUNT


def is_l(u):
    return 0x1100 <= u <= 0x115F or 0xA960 <= u <= 0xA97C


def is_v(u):
    return 0x1160 <= u <= 0x11A7 or 0xD7B0 <= u <= 0xD7C6


def is_t(u):
    return 0x11A8 <= u <= 0x11FF or 0xD7CB <= u <= 0xD7FB


def is_tone(u):
    return 0x302E <= u <= 0x302F


def replace_glyphs(b, num_in, cps):
    """HarfBuzz's replace_glyphs: num_in characters become cps, each a copy of the first."""
    b.merge_clusters(b.idx, b.idx + num_in)
    orig = b.cur() if b.idx < len(b.info) else b.out[-1]
    for u in cps:
        n = orig.copy()
        n.cp = u
        b.out.append(n)
    b.idx += num_in


class HangulShaper:
    zero_width_marks = 'none'
    no_short_circuit = False
    normalization = 'none'
    gpos_tag = None
    fallback_position = True

    def __init__(self, script):
        self.script = script
        self.masks = [0, 0, 0, 0]

    def collect_features(self, mb):
        for tag in FEATURES[1:]:
            mb.add_feature(tag)

    def override_features(self, mb):
        mb.disable_feature('calt')

    def data_create(self, m, font):
        self.masks = [0] + [m.get_1_mask(t) for t in FEATURES[1:]]

    def preprocess_text(self, b, font):
        def has(u):
            return font.nominal(u) is not None

        def zero_width(u):
            g = font.nominal(u)
            return g is not None and font.advance(g) == 0

        b.clear_output()
        start = end = 0
        count = len(b.info)
        while b.idx < count:
            u = b.cur().cp
            if is_tone(u):
                if start < end and end == len(b.out):
                    # after a syllable: in front of it, unless it overstrikes
                    b.next_glyph()
                    if not zero_width(u):
                        b.merge_out_clusters(start, end + 1)
                        tone = b.out[end]
                        b.out[start + 1:end + 1] = b.out[start:end]
                        b.out[start] = tone
                elif has(0x25CC):
                    replace_glyphs(b, 1, (0x25CC, u) if zero_width(u) else (u, 0x25CC))
                else:
                    b.next_glyph()
                start = end = len(b.out)
                continue
            start = len(b.out)
            if is_l(u) and b.idx + 1 < count:
                l, v = u, b.info[b.idx + 1].cp
                if is_v(v):
                    t, tindex = 0, 0
                    if b.idx + 2 < count:
                        t = b.info[b.idx + 2].cp
                        if is_t(t):
                            tindex = t - T_BASE
                        else:
                            t = 0
                    if is_combining_l(l) and is_combining_v(v) and (t == 0 or is_combining_t(t)):
                        s = S_BASE + (l - L_BASE) * N_COUNT + (v - V_BASE) * T_COUNT + tindex
                        if has(s):
                            replace_glyphs(b, 3 if t else 2, (s,))
                            end = start + 1
                            continue
                    b.cur().cat = LJMO
                    b.next_glyph()
                    b.cur().cat = VJMO
                    b.next_glyph()
                    if t:
                        b.cur().cat = TJMO
                        b.next_glyph()
                        end = start + 3
                    else:
                        end = start + 2
                    b.merge_out_clusters(start, end)
                    continue
            elif is_combined_s(u):
                s = u
                has_glyph = has(s)
                lindex, nindex = divmod(s - S_BASE, N_COUNT)
                vindex, tindex = divmod(nindex, T_COUNT)
                if not tindex and b.idx + 1 < count and is_combining_t(b.info[b.idx + 1].cp):
                    new_s = s + b.info[b.idx + 1].cp - T_BASE
                    if has(new_s):
                        replace_glyphs(b, 2, (new_s,))
                        end = start + 1
                        continue
                if not has_glyph or (not tindex and b.idx + 1 < count and is_t(b.info[b.idx + 1].cp)):
                    dec = (L_BASE + lindex, V_BASE + vindex, T_BASE + tindex)
                    if has(dec[0]) and has(dec[1]) and (not tindex or has(dec[2])):
                        s_len = 3 if tindex else 2
                        replace_glyphs(b, 1, dec[:s_len])
                        if has_glyph and not tindex:
                            b.next_glyph()
                            s_len += 1
                        end = start + s_len
                        i = start
                        b.out[i].cat = LJMO
                        b.out[i + 1].cat = VJMO
                        if i + 2 < end:
                            b.out[i + 2].cat = TJMO
                        b.merge_out_clusters(start, end)
                        continue
                if has_glyph:
                    end = start + 1
            b.next_glyph()
        b.sync()

    def setup_masks(self, b, font):
        for inf in b.info:
            inf.mask |= self.masks[inf.cat]

    def decompose(self, ab):
        import shapemodel as sm
        return sm.decompose2(ab)

    def compose(self, a, b):
        import shapemodel as sm
        return sm.compose(a, b)

"""HarfBuzz's Thai / Lao shaper (hb-ot-shaper-thai.cc), for shapemodel.py.

SARA AM becomes NIKHAHIT + SARA AA, the nikhahit moved back over the above-base marks before it;
for a Thai font without a thai GSUB script, marks and descenders shaped to the PUA glyphs old Thai
fonts carry (Windows' code points, else the Mac's), by the above / below state machines.
Development-machine tooling only.
"""
import shapemodel as sm

# consonant types
NC, AC, RC, DC, NOT_CONSONANT = range(5)
# mark types
AV, BV, T, NOT_MARK = range(4)
# actions
NOP, SD, SL, SDL, RD = range(5)


def consonant_type(u):
    if u in (0x0E1B, 0x0E1D, 0x0E1F):
        return AC
    if u in (0x0E0D, 0x0E10):
        return RC
    if u in (0x0E0E, 0x0E0F):
        return DC
    if 0x0E01 <= u <= 0x0E2E:
        return NC
    return NOT_CONSONANT


def mark_type(u):
    if u == 0x0E31 or 0x0E34 <= u <= 0x0E37 or u == 0x0E47 or 0x0E4D <= u <= 0x0E4E:
        return AV
    if 0x0E38 <= u <= 0x0E3A:
        return BV
    if 0x0E48 <= u <= 0x0E4C:
        return T
    return NOT_MARK


# the character, its Windows PUA, its Mac PUA
PUA = {
    SD: [(0x0E48, 0xF70A, 0xF88B), (0x0E49, 0xF70B, 0xF88E), (0x0E4A, 0xF70C, 0xF891), (0x0E4B, 0xF70D, 0xF894),
         (0x0E4C, 0xF70E, 0xF897), (0x0E38, 0xF718, 0xF89B), (0x0E39, 0xF719, 0xF89C), (0x0E3A, 0xF71A, 0xF89D)],
    SDL: [(0x0E48, 0xF705, 0xF88C), (0x0E49, 0xF706, 0xF88F), (0x0E4A, 0xF707, 0xF892), (0x0E4B, 0xF708, 0xF895),
          (0x0E4C, 0xF709, 0xF898)],
    SL: [(0x0E48, 0xF713, 0xF88A), (0x0E49, 0xF714, 0xF88D), (0x0E4A, 0xF715, 0xF890), (0x0E4B, 0xF716, 0xF893),
         (0x0E4C, 0xF717, 0xF896), (0x0E31, 0xF710, 0xF884), (0x0E34, 0xF701, 0xF885), (0x0E35, 0xF702, 0xF886),
         (0x0E36, 0xF703, 0xF887), (0x0E37, 0xF704, 0xF888), (0x0E47, 0xF712, 0xF889), (0x0E4D, 0xF711, 0xF899)],
    RD: [(0x0E0D, 0xF70F, 0xF89A), (0x0E10, 0xF700, 0xF89E)],
}


def pua_shape(u, action, font):
    for c, win, mac in PUA.get(action, ()):
        if c == u:
            if font.nominal(win) is not None:
                return win
            if font.nominal(mac) is not None:
                return mac
            break
    return u


T0, T1, T2, T3 = range(4)
ABOVE_START = [T0, T1, T0, T0, T3]
ABOVE = [[(NOP, T3), (NOP, T0), (SD, T3)],
         [(SL, T2), (NOP, T1), (SDL, T2)],
         [(NOP, T3), (NOP, T2), (SL, T3)],
         [(NOP, T3), (NOP, T3), (NOP, T3)]]
B0, B1, B2 = range(3)
BELOW_START = [B0, B0, B1, B2, B2]
BELOW = [[(NOP, B0), (NOP, B2), (NOP, B0)],
         [(NOP, B1), (RD, B2), (NOP, B1)],
         [(NOP, B2), (SD, B2), (NOP, B2)]]


def pua_shaping(b, font):
    above, below = ABOVE_START[NOT_CONSONANT], BELOW_START[NOT_CONSONANT]
    base = 0
    info = b.info
    for i in range(len(info)):
        mt = mark_type(info[i].cp)
        if mt == NOT_MARK:
            ct = consonant_type(info[i].cp)
            above, below = ABOVE_START[ct], BELOW_START[ct]
            base = i
            continue
        a_action, above = ABOVE[above][mt]
        b_action, below = BELOW[below][mt]
        action = a_action if a_action != NOP else b_action
        if action == RD:
            info[base].cp = pua_shape(info[base].cp, action, font)
        else:
            info[i].cp = pua_shape(info[i].cp, action, font)


def is_above_base_mark(u):
    u &= ~0x80
    return 0x0E34 <= u <= 0x0E37 or 0x0E47 <= u <= 0x0E4E or u == 0x0E31 or u == 0x0E3B


class ThaiShaper:
    zero_width_marks = 'late'
    no_short_circuit = False
    gpos_tag = None
    fallback_position = False

    def __init__(self, script):
        self.script = script
        self.found_script = False

    def collect_features(self, mb):
        pass

    def override_features(self, mb):
        pass

    def data_create(self, m, font):
        pass

    def preprocess_text(self, b, font):
        b.clear_output()
        while b.idx < len(b.info):
            u = b.cur().cp
            if (u & ~0x80) != 0x0E33:
                b.next_glyph()
                continue
            # SARA AM: NIKHAHIT + SARA AA (both keep SARA AM's properties; the nikhahit a
            # continuing nonspacing mark of class 0)
            nik = b.cur().copy()
            nik.cp = u - 0x0E33 + 0x0E4D
            nik.cont = True
            nik.gc = 'Mn'
            nik.mcc = 0
            b.output_info(nik)
            aa = b.cur().copy()
            aa.cp = u - 1
            b.output_info(aa)
            b.idx += 1
            end = len(b.out)
            start = end - 2
            while start > 0 and is_above_base_mark(b.out[start - 1].cp):
                start -= 1
            if start + 2 < end:
                b.merge_out_clusters(start, end)
                t = b.out[end - 2]
                b.out[start + 1:end - 1] = b.out[start:end - 2]
                b.out[start] = t
            elif start:
                b.merge_out_clusters(start - 1, end)
        b.sync()
        if self.script == 'Thai' and not self.found_script:
            pua_shaping(b, font)

    def setup_masks(self, b, font):
        pass

    def decompose(self, ab):
        return sm.decompose2(ab)

    def compose(self, a, b):
        return sm.compose(a, b)

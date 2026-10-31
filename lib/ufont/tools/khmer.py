"""HarfBuzz's Khmer shaper (hb-ot-shaper-khmer.cc), for shapemodel.py.

Syllables by the Khmer grammar over the characters' categories (tools/indic_data.py); dotted
circles in broken clusters; per syllable: blwf / abvf / pstf on everything after the base, a
COENG + RO moved before the base with pref (and cfar on what follows it), a pre-base vowel moved
to the start; locl, ccmp and the basic features per syllable, then pres / abvs / blws / psts
everywhere; clig on, liga off; split vowels decomposed (U+17BE .. U+17C5 into U+17C1 + the
vowel), nothing composed onto a mark, no short circuit; no mark zeroing, no fallback positioning.
Development-machine tooling only.
"""
import shapemodel as sm
import syllable as syl
import syllabic
from indic_data import TABLE

# categories (HarfBuzz's numbers)
C, V, H, ZWNJ, ZWJ, PLACEHOLDER, DOTTEDCIRCLE, RA = 1, 2, 4, 5, 6, 10, 11, 15
VABV, VBLW, VPRE, VPST, ROBATIC, XGROUP, YGROUP = 20, 21, 22, 23, 25, 26, 27
# syllable types
CONSONANT_SYLLABLE, BROKEN_CLUSTER, NON_KHMER_CLUSTER = range(3)


def _grammar():
    cat, seq, alt, opt, star = syl.cat, syl.seq, syl.alt, syl.opt, syl.star
    c = cat(C, RA, V)
    joiner = cat(ZWJ, ZWNJ)
    cn = seq(c, opt(seq(opt(joiner), cat(ROBATIC))))
    xgroup = star(seq(star(joiner), cat(XGROUP)))
    ygroup = star(cat(YGROUP))
    matra_group = seq(opt(cat(VPRE)), xgroup, opt(cat(VBLW)), xgroup, opt(seq(opt(joiner), cat(VABV))), xgroup,
                      opt(cat(VPST)))
    syllable_tail = seq(xgroup, matra_group, xgroup, opt(seq(cat(H), c)), ygroup)
    broken_cluster = seq(opt(cat(ROBATIC)), star(seq(cat(H), cn)), alt(cat(H), syllable_tail))
    consonant_syllable = seq(alt(cn, cat(PLACEHOLDER), cat(DOTTEDCIRCLE)), broken_cluster)
    return [(consonant_syllable, CONSONANT_SYLLABLE), (broken_cluster, BROKEN_CLUSTER),
            (syl.ANY, NON_KHMER_CLUSTER)]


GRAMMAR = _grammar()
MACHINE = syl.dfa(GRAMMAR, [C, V, H, ZWNJ, ZWJ, PLACEHOLDER, DOTTEDCIRCLE, RA, VABV, VBLW, VPRE, VPST, ROBATIC,
                            XGROUP, YGROUP])

PS = sm.F_PER_SYLLABLE
BASIC = [('pref', sm.F_MANUAL_JOINERS | PS), ('blwf', sm.F_MANUAL_JOINERS | PS), ('abvf', sm.F_MANUAL_JOINERS | PS),
         ('pstf', sm.F_MANUAL_JOINERS | PS), ('cfar', sm.F_MANUAL_JOINERS | PS)]
OTHER = [('pres', sm.F_GLOBAL_MANUAL_JOINERS), ('abvs', sm.F_GLOBAL_MANUAL_JOINERS),
         ('blws', sm.F_GLOBAL_MANUAL_JOINERS), ('psts', sm.F_GLOBAL_MANUAL_JOINERS)]
SPLIT = {0x17BE: 0x17BE, 0x17BF: 0x17BF, 0x17C0: 0x17C0, 0x17C4: 0x17C4, 0x17C5: 0x17C5}


class KhmerShaper:
    zero_width_marks = 'none'
    no_short_circuit = True
    gpos_tag = None
    fallback_position = False

    def __init__(self, script):
        self.script = script
        self.has_broken = False

    def collect_features(self, mb):
        mb.add_gsub_pause(self.setup_syllables)
        mb.add_gsub_pause(self.reorder)
        mb.enable_feature('locl', PS)
        mb.enable_feature('ccmp', PS)
        for tag, flags in BASIC:
            mb.add_feature(tag, flags)
        mb.add_gsub_pause(syllabic.clear_syllables)
        for tag, flags in OTHER:
            mb.add_feature(tag, flags)

    def override_features(self, mb):
        mb.enable_feature('clig')
        mb.disable_feature('liga')

    def data_create(self, m, font):
        self.font = font
        self.mask = {tag: 0 if flags & sm.F_GLOBAL else m.get_1_mask(tag) for tag, flags in BASIC + OTHER}

    def preprocess_text(self, b, font):
        pass

    def decompose(self, ab):
        if ab in SPLIT:
            return 0x17C1, ab
        return sm.decompose2(ab)

    def compose(self, a, b):
        if sm.is_mark_gc(sm.gc(a)):
            return None
        return sm.compose(a, b)

    def setup_masks(self, b, font):
        for inf in b.info:
            inf.cat = TABLE.get(inf.cp, (0, 14))[0]

    # --- pauses
    def setup_syllables(self, b):
        self.has_broken = syllabic.find_syllables(b, MACHINE, [inf.cat for inf in b.info], BROKEN_CLUSTER)

    def reorder(self, b):
        if self.has_broken:
            syllabic.insert_dotted_circles(b, self.font, BROKEN_CLUSTER, DOTTEDCIRCLE)
        for start, end in list(syllabic.syllables(b)):
            if (b.info[start].syllable & 0x0F) in (BROKEN_CLUSTER, CONSONANT_SYLLABLE):
                self.reorder_consonant_syllable(b, start, end)

    def reorder_consonant_syllable(self, b, start, end):
        info, mask = b.info, self.mask
        post = mask['blwf'] | mask['abvf'] | mask['pstf']
        for i in range(start + 1, end):
            info[i].mask |= post
        num_coengs = 0
        i = start + 1
        while i < end:
            if info[i].cat == H and num_coengs <= 2 and i + 1 < end:
                num_coengs += 1
                if info[i + 1].cat == RA:
                    info[i].mask |= mask['pref']
                    info[i + 1].mask |= mask['pref']
                    # COENG + RO to the start
                    b.merge_clusters(start, i + 2)
                    t0, t1 = info[i], info[i + 1]
                    info[start + 2:i + 2] = info[start:i]
                    info[start], info[start + 1] = t0, t1
                    if mask['cfar']:
                        for j in range(i + 2, end):
                            info[j].mask |= mask['cfar']
                    num_coengs = 2
            elif info[i].cat == VPRE:
                b.merge_clusters(start, i + 1)
                t = info[i]
                info[start + 1:i + 1] = info[start:i]
                info[start] = t
            i += 1

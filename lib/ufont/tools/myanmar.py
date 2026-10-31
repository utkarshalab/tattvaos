"""HarfBuzz's Myanmar shaper (hb-ot-shaper-myanmar.cc), for shapemodel.py.

Syllables by the Myanmar grammar over the characters' categories (tools/indic_data.py); dotted
circles in broken clusters; initial reordering of each syllable (kinzi after the main part, the
base, medial RA and pre-base vowels before it, below and after parts by position), sorted, a run
of pre-base vowels flipped; locl and ccmp, then rphf / pref / blwf / pstf one at a time, all held
to the syllable; then the syllables cleared and pres / abvs / blws / psts. No short circuit,
marks' widths zeroed before GPOS, no fallback positioning. Fonts with only DFLT, latn or the old
mymr script take the default shaper. Development-machine tooling only.
"""
import shapemodel as sm
import syllable as syl
import syllabic
from indic_data import TABLE

# categories (HarfBuzz's numbers)
C, IV, DB, H, ZWNJ, ZWJ, SM, A, GB, DOTTEDCIRCLE, RA, CS = 1, 2, 3, 4, 5, 6, 8, 9, 10, 11, 15, 18
VABV, VBLW, VPRE, VPST, AS, MH, MR, MW, MY, PT, VS, ML, SMPST = 20, 21, 22, 23, 32, 35, 36, 37, 38, 39, 40, 41, 57
# positions
PRE_M, PRE_C, BASE_C, AFTER_MAIN, BEFORE_SUB, BELOW_C, AFTER_SUB = 2, 3, 4, 5, 7, 8, 9
# syllable types
CONSONANT_SYLLABLE, BROKEN_CLUSTER, NON_MYANMAR_CLUSTER = range(3)

CONSONANT_FLAGS = (1 << C) | (1 << CS) | (1 << RA) | (1 << IV) | (1 << GB) | (1 << DOTTEDCIRCLE)


def _grammar():
    cat, seq, alt, opt, star = syl.cat, syl.seq, syl.alt, syl.opt, syl.star
    j = cat(ZWJ, ZWNJ)
    k = seq(cat(RA), cat(AS), cat(H))
    sm_ = cat(SM, SMPST)
    c = cat(C, RA)
    medial_group = seq(opt(cat(MY)), opt(cat(AS)), opt(cat(MR)),
                       opt(seq(alt(seq(cat(MW), opt(cat(MH)), opt(cat(ML))), seq(cat(MH), opt(cat(ML))), cat(ML)),
                               opt(cat(AS)))))
    db_as = opt(seq(cat(DB), opt(cat(AS))))
    main_vowel_group = seq(star(seq(cat(VPRE), opt(cat(VS)))), star(cat(VABV)), star(cat(VBLW)), star(cat(A)), db_as)
    post_vowel_group = seq(cat(VPST), opt(cat(MH)), opt(cat(ML)), star(cat(AS)), star(cat(VABV)), star(cat(A)), db_as)
    tone_group = alt(sm_, seq(cat(PT), star(cat(A)), opt(cat(DB)), opt(cat(AS))))
    complex_syllable_tail = seq(star(cat(AS)), medial_group, main_vowel_group, star(post_vowel_group),
                                star(tone_group), opt(j))
    syllable_tail = seq(star(seq(cat(H), cat(C, RA, IV), opt(cat(VS)))), alt(cat(H), complex_syllable_tail))
    consonant_syllable = seq(opt(alt(k, cat(CS))), cat(C, RA, IV, GB, DOTTEDCIRCLE), opt(cat(VS)), syllable_tail)
    broken_cluster = seq(opt(k), opt(cat(VS)), syllable_tail)
    return [(consonant_syllable, CONSONANT_SYLLABLE), (alt(j, cat(SMPST)), NON_MYANMAR_CLUSTER),
            (broken_cluster, BROKEN_CLUSTER), (syl.ANY, NON_MYANMAR_CLUSTER)]


GRAMMAR = _grammar()
MACHINE = syl.dfa(GRAMMAR, [C, IV, DB, H, ZWNJ, ZWJ, SM, A, GB, DOTTEDCIRCLE, RA, CS, VABV, VBLW, VPRE, VPST, AS,
                            MH, MR, MW, MY, PT, VS, ML, SMPST])

PS = sm.F_PER_SYLLABLE
BASIC = ('rphf', 'pref', 'blwf', 'pstf')
OTHER = ('pres', 'abvs', 'blws', 'psts')


def is_consonant(info):
    if info.props & sm.LIGATED:
        return False
    return info.cat < 32 and bool((1 << info.cat) & CONSONANT_FLAGS)


class MyanmarShaper:
    zero_width_marks = 'early'
    no_short_circuit = True
    gpos_tag = None
    fallback_position = False

    def __init__(self, script):
        self.script = script
        self.has_broken = False

    def collect_features(self, mb):
        mb.add_gsub_pause(self.setup_syllables)
        mb.enable_feature('locl', PS)
        mb.enable_feature('ccmp', PS)
        mb.add_gsub_pause(self.reorder)
        for tag in BASIC:
            mb.enable_feature(tag, sm.F_MANUAL_ZWJ | PS)
            mb.add_gsub_pause(None)
        mb.add_gsub_pause(syllabic.clear_syllables)
        for tag in OTHER:
            mb.enable_feature(tag, sm.F_MANUAL_ZWJ)

    def override_features(self, mb):
        pass

    def data_create(self, m, font):
        self.font = font

    def preprocess_text(self, b, font):
        pass

    def decompose(self, ab):
        return sm.decompose2(ab)

    def compose(self, a, b):
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
        info = b.info
        base, has_reph, limit = end, False, start
        if start + 3 <= end and info[start].cat == RA and info[start + 1].cat == AS and info[start + 2].cat == H:
            limit += 3
            base = start
            has_reph = True
        if not has_reph:
            base = limit
        for i in range(limit, end):
            if is_consonant(info[i]):
                base = i
                break
        i = start
        while i < start + (3 if has_reph else 0):
            info[i].pos = AFTER_MAIN
            i += 1
        while i < base:
            info[i].pos = PRE_C
            i += 1
        if i < end:
            info[i].pos = BASE_C
            i += 1
        pos = AFTER_MAIN
        while i < end:
            cat = info[i].cat
            if cat == MR:
                info[i].pos = PRE_C
            elif cat == VPRE:
                info[i].pos = PRE_M
            elif cat == VS:
                info[i].pos = info[i - 1].pos
            elif pos == AFTER_MAIN and cat == VBLW:
                pos = BELOW_C
                info[i].pos = pos
            elif pos == BELOW_C and cat == A:
                info[i].pos = BEFORE_SUB
            elif pos == BELOW_C and cat == VBLW:
                info[i].pos = pos
            elif pos == BELOW_C:
                pos = AFTER_SUB
                info[i].pos = pos
            else:
                info[i].pos = pos
            i += 1
        b.sort(start, end, lambda inf: inf.pos)
        info = b.info
        # a run of pre-base vowels flipped (their variation selectors kept after them)
        first = last = end
        for i in range(start, end):
            if info[i].pos == PRE_M:
                if first == end:
                    first = i
                last = i
        if first < last:
            info[first:last + 1] = info[first:last + 1][::-1]
            i = first
            for j in range(first, last + 1):
                if info[j].cat == VPRE:
                    info[i:j + 1] = info[i:j + 1][::-1]
                    i = j + 1

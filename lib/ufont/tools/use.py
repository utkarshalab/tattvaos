"""HarfBuzz's Universal Shaping Engine (hb-ot-shaper-use.cc), for shapemodel.py.

Characters get USE categories (tools/use_data.py); syllables come from the USE grammar run over
the text without its CGJ-class characters (and without a ZWNJ a mark follows), each skipped
character joining the syllable before it; rphf goes on a syllable's repha (or its first three
glyphs), the topographical features (isol / init / medi / fina) on whole syllables as they join
(or, for scripts that join like Arabic, Arabic joining's forms). The plan: locl, ccmp, nukt, akhn;
rphf, then the substituted repha recorded as R; pref, a substituted pref recorded as VPre (the
substitution flags cleared before each); rkrf, abvf, blwf, half, pstf, vatu, cjct; reordering
(dotted circles in broken clusters after their repha, a repha moved to before the first post-base
glyph, pre-base vowels and vowel modifiers moved back after the last halant); the syllables
cleared; the topographical features; abvs, blws, haln, pres, psts. Vowel constraints first; no
short circuit, nothing composed onto a mark; marks zeroed before GPOS, no fallback positioning.
Development-machine tooling only.
"""
import shapemodel as sm
import syllable as syl
import syllabic
import arabic
from use_data import TABLE
from vowel_data import VOWEL_CONSTRAINTS

# categories (HarfBuzz's numbers)
O, B, N, GB, CGJ, SUB, H, HN, ZWNJ, WJ, R = 0, 1, 4, 5, 6, 11, 12, 13, 14, 16, 18
CS, IS, SK, G, J, SB, SE, HVM, HM, HR, RK = 43, 44, 48, 49, 50, 51, 52, 53, 54, 55, 56
FABV, FBLW, FPST, MABV, MBLW, MPST, MPRE, CMABV, CMBLW = 24, 25, 26, 27, 28, 29, 30, 31, 32
VABV, VBLW, VPST, VPRE, VMABV, VMBLW, VMPST, VMPRE = 33, 34, 35, 22, 37, 38, 39, 23
SMABV, SMBLW, FMABV, FMBLW, FMPST = 41, 42, 45, 46, 47
# syllable types
(VIRAMA_TERMINATED, SAKOT_TERMINATED, STANDARD, NUMBER_JOINER_TERMINATED, NUMERAL, SYMBOL, HIEROGLYPH,
 BROKEN_CLUSTER, NON_CLUSTER) = range(9)

# the scripts HarfBuzz shapes with the USE (and the Indic ones whose font has a xxx3 script)
SCRIPTS = set('Tibt Mong Sinh Buhd Hano Tglg Tagb Limb Tale Bugi Khar Sylo Tfng Bali Nkoo Phag Cham Kali Lepc Rjng '
              'Saur Sund Egyp Java Kthi Mtei Lana Tavt Batk Brah Mand Cakm Plrd Shrd Takr Dupl Gran Khoj Sind Mahj '
              'Mani Modi Hmng Phlp Sidd Tirh Ahom Mult Adlm Bhks Marc Newa Gonm Soyo Zanb Dogr Gong Rohg Maka Medf '
              'Sogo Sogd Elym Nand Hmnp Wcho Chrs Diak Kits Yezi Cpmn Ougr Tnsa Toto Vith Kawi Nagm Gara Gukh Krai '
              'Onao Sunu Todr Tutg Berf Sidt Tayo Tols'.split())
# the scripts that join like Arabic (HarfBuzz's has_arabic_joining)
ARABIC_JOINING = {'Adlm', 'Arab', 'Chrs', 'Rohg', 'Mand', 'Mani', 'Mong', 'Nkoo', 'Ougr', 'Phag', 'Phlp', 'Sogd', 'Syrc'}


def _grammar():
    cat, seq, alt, opt, star = syl.cat, syl.seq, syl.alt, syl.opt, syl.star

    def plus(p):
        return seq(p, star(p))

    h = cat(H, HVM, IS, SK)
    consonant_modifiers = seq(star(cat(CMABV)), star(cat(CMBLW)),
                              star(seq(alt(seq(h, cat(B)), cat(SUB)), star(cat(CMABV)), star(cat(CMBLW)))))
    medial_consonants = seq(opt(cat(MPRE)), opt(cat(MABV)), opt(cat(MBLW)), opt(cat(MPST)))
    dependent_vowels = alt(seq(star(cat(VPRE)), star(cat(VABV)), star(cat(VBLW)), star(cat(VPST))), cat(H))
    vowel_modifiers = seq(opt(cat(HVM)), star(cat(VMPRE)), star(cat(VMABV)), star(cat(VMBLW)), star(cat(VMPST)))
    final_consonants = seq(star(cat(FABV)), star(cat(FBLW)), star(cat(FPST)))
    final_modifiers = alt(seq(star(cat(FMABV)), star(cat(FMBLW))), opt(cat(FMPST)))
    complex_syllable_start = seq(opt(cat(R, CS)), cat(B, GB))
    complex_syllable_middle = seq(consonant_modifiers, medial_consonants, dependent_vowels, vowel_modifiers,
                                  star(seq(cat(SK), cat(B))))
    complex_syllable_tail = seq(complex_syllable_middle, final_consonants, final_modifiers)
    number_joiner_terminated_cluster_tail = seq(star(seq(cat(HN), cat(N))), cat(HN))
    numeral_cluster_tail = plus(seq(cat(HN), cat(N)))
    symbol_cluster_tail = alt(seq(plus(cat(SMABV)), star(cat(SMBLW))), plus(cat(SMBLW)))
    virama_terminated_cluster_tail = seq(consonant_modifiers, cat(IS, RK))
    virama_terminated_cluster = seq(complex_syllable_start, virama_terminated_cluster_tail)
    sakot_terminated_cluster_tail = seq(complex_syllable_middle, cat(SK))
    sakot_terminated_cluster = seq(complex_syllable_start, sakot_terminated_cluster_tail)
    standard_cluster = seq(complex_syllable_start, complex_syllable_tail)
    tail = alt(complex_syllable_tail, sakot_terminated_cluster_tail, symbol_cluster_tail,
               virama_terminated_cluster_tail)
    broken_cluster = seq(opt(cat(R)), alt(tail, number_joiner_terminated_cluster_tail, numeral_cluster_tail))
    number_joiner_terminated_cluster = seq(cat(N), number_joiner_terminated_cluster_tail)
    numeral_cluster = seq(cat(N), opt(numeral_cluster_tail))
    symbol_cluster = seq(cat(O, GB, SB), opt(tail))
    glyph = seq(cat(G), opt(cat(HR)), opt(cat(HM)), star(cat(SE)))
    hieroglyph_cluster = seq(star(cat(SB)), glyph, star(seq(cat(J), star(cat(SB)), opt(glyph))))
    z = opt(cat(ZWNJ))
    return [(seq(virama_terminated_cluster, z), VIRAMA_TERMINATED),
            (seq(sakot_terminated_cluster, z), SAKOT_TERMINATED),
            (seq(standard_cluster, z), STANDARD),
            (seq(number_joiner_terminated_cluster, z), NUMBER_JOINER_TERMINATED),
            (seq(numeral_cluster, z), NUMERAL),
            (seq(symbol_cluster, z), SYMBOL),
            (seq(hieroglyph_cluster, z), HIEROGLYPH),
            (cat(FMPST), NON_CLUSTER),
            (seq(broken_cluster, z), BROKEN_CLUSTER),
            (syl.ANY, NON_CLUSTER)]


GRAMMAR = _grammar()
MACHINE = syl.dfa(GRAMMAR, [O, B, N, GB, CGJ, SUB, H, HN, ZWNJ, WJ, R, CS, IS, SK, G, J, SB, SE, HVM, HM, HR, RK,
                            FABV, FBLW, FPST, MABV, MBLW, MPST, MPRE, CMABV, CMBLW, VABV, VBLW, VPST, VPRE, VMABV,
                            VMBLW, VMPST, VMPRE, SMABV, SMBLW, FMABV, FMBLW, FMPST])

PS = sm.F_PER_SYLLABLE
BASIC = ('rkrf', 'abvf', 'blwf', 'half', 'pstf', 'vatu', 'cjct')
TOPOGRAPHICAL = ('isol', 'init', 'medi', 'fina')
ISOL, INIT, MEDI, FINA, NO_FORM = range(5)
OTHER = ('abvs', 'blws', 'haln', 'pres', 'psts')
POST_BASE = {FABV, FBLW, FPST, FMABV, FMBLW, FMPST, MABV, MBLW, MPST, MPRE, VABV, VBLW, VPST, VPRE, VMABV, VMBLW,
             VMPST, VMPRE}


def is_halant(info):
    return info.cat in (H, HVM, IS) and not info.props & sm.LIGATED


class UseShaper:
    zero_width_marks = 'early'
    no_short_circuit = True
    gpos_tag = None
    fallback_position = False

    def __init__(self, script):
        self.script = script
        self.arabic = script in ARABIC_JOINING
        self.has_broken = False

    # --- the plan
    def collect_features(self, mb):
        mb.add_gsub_pause(self.setup_syllables)
        mb.enable_feature('locl', PS)
        mb.enable_feature('ccmp', PS)
        mb.enable_feature('nukt', PS)
        mb.enable_feature('akhn', sm.F_MANUAL_ZWJ | PS)
        mb.add_gsub_pause(clear_substitution_flags)
        mb.add_feature('rphf', sm.F_MANUAL_ZWJ | PS)
        mb.add_gsub_pause(self.record_rphf)
        mb.add_gsub_pause(clear_substitution_flags)
        mb.enable_feature('pref', sm.F_MANUAL_ZWJ | PS)
        mb.add_gsub_pause(record_pref)
        for tag in BASIC:
            mb.enable_feature(tag, sm.F_MANUAL_ZWJ | PS)
        mb.add_gsub_pause(self.reorder)
        mb.add_gsub_pause(syllabic.clear_syllables)
        for tag in TOPOGRAPHICAL:
            mb.add_feature(tag)
        mb.add_gsub_pause(None)
        for tag in OTHER:
            mb.enable_feature(tag, sm.F_MANUAL_ZWJ)

    def override_features(self, mb):
        pass

    def data_create(self, m, font):
        self.font = font
        self.rphf_mask = m.get_1_mask('rphf')
        self.arabic_masks = [m.get_1_mask(tag) for tag in arabic.FEATURES] + [0]
        self.topo_masks = [m.get_1_mask(tag) for tag in TOPOGRAPHICAL]
        self.topo_masks = [0 if mk == m.global_mask else mk for mk in self.topo_masks]

    # --- before normalization
    def preprocess_text(self, b, font):
        """Vowel constraints: a dotted circle where a vowel and a sign would read as another vowel."""
        b.clear_output()
        count = len(b.info)
        pairs = set(VOWEL_CONSTRAINTS.get(self.script, ()))
        if pairs:
            b.idx = 0
            while b.idx + 1 < count:
                u, nxt = b.cur().cp, b.info[b.idx + 1].cp
                matched = (u, nxt) in pairs
                if self.script == 'Deva' and u == 0x0930 and nxt == 0x094D and b.idx + 2 < count and \
                        b.info[b.idx + 2].cp == 0x0907:
                    b.next_glyph()
                    matched = True
                b.next_glyph()
                if matched:
                    dc = b.cur().copy()
                    dc.cp = 0x25CC
                    dc.cont = False
                    b.out.append(dc)
                    b.next_glyph()
        b.sync()

    def decompose(self, ab):
        return sm.decompose2(ab)

    def compose(self, a, b):
        if sm.is_mark_gc(sm.gc(a)):
            return None
        return sm.compose(a, b)

    def setup_masks(self, b, font):
        info = b.info
        if self.arabic:
            prev, state = None, 0
            actions = [arabic.NONE] * len(info)
            for i, inf in enumerate(info):
                t = arabic.joining_type(inf.cp, inf.gc)
                if t == arabic.JT_T:
                    continue
                pa, ca, ns = arabic.STATES[state][t]
                if pa != arabic.NONE and prev is not None:
                    actions[prev] = pa
                actions[i] = ca
                prev, state = i, ns
            if self.script == 'Mong':
                # Mongolian free variation selectors take their base's form
                for i in range(1, len(info)):
                    if 0x180B <= info[i].cp <= 0x180D or info[i].cp == 0x180F:
                        actions[i] = actions[i - 1]
            for inf, a in zip(info, actions):
                inf.mask |= self.arabic_masks[a]
        for inf in info:
            inf.cat = TABLE.get(inf.cp, O)

    # --- pauses
    def setup_syllables(self, b):
        info, n = b.info, len(b.info)
        # the characters the grammar sees: not CGJ-class, not a ZWNJ before a mark
        seen = []
        for i, inf in enumerate(info):
            if inf.cat == CGJ:
                continue
            if inf.cat == ZWNJ:
                nxt = next((k for k in range(i + 1, n) if info[k].cat != CGJ), None)
                if nxt is not None and sm.is_mark_gc(info[nxt].gc):
                    continue
            seen.append(i)
        serial = 1
        for start, end, typ in syl.scan(MACHINE, [info[i].cat for i in seen]):
            first, last = seen[start], (seen[end] if end < len(seen) else n)
            for i in range(first, last):
                info[i].syllable = (serial << 4) | typ
            serial += 1
            if serial == 16:
                serial = 1
            self.has_broken |= typ == BROKEN_CLUSTER
        self.setup_rphf_mask(b)
        self.setup_topographical_masks(b)

    def setup_rphf_mask(self, b):
        mask = self.rphf_mask
        if not mask:
            return
        info = b.info
        for start, end in syllabic.syllables(b):
            limit = 1 if info[start].cat == R else min(3, end - start)
            for i in range(start, start + limit):
                info[i].mask |= mask

    def setup_topographical_masks(self, b):
        if self.arabic:
            return
        masks = self.topo_masks
        all_masks = masks[0] | masks[1] | masks[2] | masks[3]
        if not all_masks:
            return
        other = ~all_masks
        info = b.info
        last_start, last_form = 0, NO_FORM
        for start, end in syllabic.syllables(b):
            typ = info[start].syllable & 0x0F
            if typ in (HIEROGLYPH, NON_CLUSTER):
                last_form = NO_FORM
            else:
                join = last_form in (FINA, ISOL)
                if join:
                    last_form = MEDI if last_form == FINA else INIT
                    for i in range(last_start, start):
                        info[i].mask = (info[i].mask & other) | masks[last_form]
                last_form = FINA if join else ISOL
                for i in range(start, end):
                    info[i].mask = (info[i].mask & other) | masks[last_form]
            last_start = start

    def record_rphf(self, b):
        mask = self.rphf_mask
        if not mask:
            return
        info = b.info
        for start, end in syllabic.syllables(b):
            i = start
            while i < end and info[i].mask & mask:
                if info[i].props & sm.SUBSTITUTED:
                    info[i].cat = R
                    break
                i += 1

    def reorder(self, b):
        if self.has_broken:
            syllabic.insert_dotted_circles(b, self.font, BROKEN_CLUSTER, B, R)
        for start, end in list(syllabic.syllables(b)):
            self.reorder_syllable(b, start, end)

    def reorder_syllable(self, b, start, end):
        info = b.info
        if (info[start].syllable & 0x0F) not in (VIRAMA_TERMINATED, SAKOT_TERMINATED, STANDARD, SYMBOL,
                                                 BROKEN_CLUSTER):
            return
        # a repha towards the end, before the first post-base glyph
        if info[start].cat == R and end - start > 1:
            for i in range(start + 1, end):
                post = info[i].cat in POST_BASE or is_halant(info[i])
                if post or i == end - 1:
                    if post:
                        i -= 1
                    b.merge_clusters(start, i + 1)
                    t = info[start]
                    info[start:i] = info[start + 1:i + 1]
                    info[i] = t
                    break
        # pre-base vowels and vowel modifiers back, after the last halant
        j = start
        for i in range(start, end):
            if is_halant(info[i]):
                j = i + 1
            elif info[i].cat in (VPRE, VMPRE) and info[i].lig_comp() == 0 and j < i:
                b.merge_clusters(j, i + 1)
                t = info[i]
                info[j + 1:i + 1] = info[j:i]
                info[j] = t


def clear_substitution_flags(b):
    for inf in b.info:
        inf.props &= ~sm.SUBSTITUTED


def record_pref(b):
    info = b.info
    for start, end in syllabic.syllables(b):
        for i in range(start, end):
            if info[i].props & sm.SUBSTITUTED:
                info[i].cat = VPRE
                break

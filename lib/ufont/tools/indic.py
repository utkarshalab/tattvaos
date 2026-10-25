#!/usr/bin/env python3
"""A model of lib/ufont's Indic shaper (Devanagari), used by tools/shapemodel.py.

It does what HarfBuzz's Indic shaper does, step for step, so the two agree glyph
for glyph:

- vowel constraints: a dotted circle between an independent vowel and a sign
  that would make it look like another vowel (U+0905 U+093E, ...);
- normalization without the short circuit (every character decomposed against
  the font first), U+0931 never decomposed, nothing composed onto a mark;
- each character's syllable category and position (tools/indic_data.py) and
  its syllables (the grammar below, tools/syllable.py);
- the feature plan: locl / ccmp, initial reordering, then nukt, akhn, rphf,
  rkrf, pref, blwf, abvf, half, pstf, vatu, cjct each applied on its own, final
  reordering, then init, pres, abvs, blws, psts, haln with the common features,
  liga off; every one of them confined to the syllable;
- initial reordering: consonant positions from the font (a consonant whose
  halant form blwf / vatu / pstf / pref would substitute sits below / after the
  base), dotted circles for broken clusters, the base consonant, reph,
  pre-base matras and halants, the syllable sorted by position and the masks
  that decide which feature applies where;
- final reordering after the basic features: the pre-base matra and reph
  moved to their places, pref, init;
- no mark widths zeroed.

Development-machine tooling only; not part of any OS image.
"""
import shapemodel as sm
import syllable as syl
from indic_data import TABLE

# syllable categories
X, C, V, N, H, ZWNJ, ZWJ, M, SM, A, PLACEHOLDER, DOTTEDCIRCLE = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
RS, MPST, REPHA, RA, CM, SYMBOL, CS, SMPST = 12, 13, 14, 15, 16, 17, 18, 57
# positions
START, RA_TO_BECOME_REPH, PRE_M, PRE_C, BASE_C, AFTER_MAIN, ABOVE_C = 0, 1, 2, 3, 4, 5, 6
BEFORE_SUB, BELOW_C, AFTER_SUB, BEFORE_POST, POST_C, AFTER_POST, SMVD, END = 7, 8, 9, 10, 11, 12, 13, 14
# syllable types
CONSONANT_SYLLABLE, VOWEL_SYLLABLE, STANDALONE_CLUSTER, SYMBOL_CLUSTER, BROKEN_CLUSTER, NON_INDIC = range(6)
# reph and blwf modes
REPH_IMPLICIT, REPH_EXPLICIT, REPH_LOG_REPHA = 0, 1, 2
BLWF_PRE_AND_POST, BLWF_POST_ONLY = 0, 1


def flag(x):
    return 1 << x if x < 32 else 0


CONSONANT_FLAGS = flag(C) | flag(CS) | flag(RA) | flag(CM) | flag(V) | flag(PLACEHOLDER) | flag(DOTTEDCIRCLE)
JOINER_FLAGS = flag(ZWJ) | flag(ZWNJ)
MATRA_FLAGS = flag(M) | flag(MPST)


# ---------------------------------------------------------------- the grammar
def _grammar():
    cat, seq, alt, opt, star = syl.cat, syl.seq, syl.alt, syl.opt, syl.star
    c = cat(C, RA)
    n = seq(opt(seq(opt(cat(ZWNJ)), cat(RS))), opt(seq(cat(N), opt(cat(N)))))
    z = cat(ZWJ, ZWNJ)
    reph = alt(seq(cat(RA), cat(H)), cat(REPHA))
    sm_ = cat(SM, SMPST)
    cn = seq(c, opt(cat(ZWJ)), opt(n))
    symbol = seq(cat(SYMBOL), opt(cat(N)))
    matra_group = seq(star(z), alt(cat(M), seq(opt(sm_), cat(MPST))), opt(cat(N)), opt(cat(H)))
    syllable_tail = seq(opt(seq(opt(z), sm_, opt(sm_), opt(cat(ZWNJ)))), star(cat(A)))
    halant_group = seq(opt(z), cat(H), opt(seq(cat(ZWJ), opt(cat(N)))))
    final_halant_group = alt(halant_group, seq(cat(H), cat(ZWNJ)))
    medial_group = opt(cat(CM))
    halant_or_matra_group = alt(final_halant_group, star(matra_group))
    complex_syllable_tail = seq(star(seq(halant_group, cn)), medial_group, halant_or_matra_group, syllable_tail)
    consonant_syllable = seq(opt(cat(REPHA, CS)), cn, complex_syllable_tail)
    vowel_syllable = seq(opt(reph), cat(V), opt(n), alt(cat(ZWJ), complex_syllable_tail))
    standalone_cluster = seq(alt(seq(opt(cat(REPHA, CS)), cat(PLACEHOLDER)), seq(opt(reph), cat(DOTTEDCIRCLE))),
                             opt(n), complex_syllable_tail)
    symbol_cluster = seq(symbol, syllable_tail)
    broken_cluster = seq(opt(reph), opt(n), complex_syllable_tail)
    return [(consonant_syllable, CONSONANT_SYLLABLE), (vowel_syllable, VOWEL_SYLLABLE),
            (standalone_cluster, STANDALONE_CLUSTER), (symbol_cluster, SYMBOL_CLUSTER),
            (cat(SMPST), NON_INDIC), (broken_cluster, BROKEN_CLUSTER), (syl.ANY, NON_INDIC)]


GRAMMAR = _grammar()
MACHINE = syl.dfa(GRAMMAR, [X, C, V, N, H, ZWNJ, ZWJ, M, SM, A, PLACEHOLDER, DOTTEDCIRCLE, RS, MPST, REPHA, RA,
                            CM, SYMBOL, CS, SMPST])

# script configurations: has old spec, virama, reph position, reph mode, blwf mode
CONFIGS = {
    'Deva': (True, 0x094D, BEFORE_POST, REPH_IMPLICIT, BLWF_PRE_AND_POST),
}

# the features: (tag, flags); the first eleven one stage each before final reordering
PS = sm.F_PER_SYLLABLE
FEATURES = [('nukt', sm.F_GLOBAL_MANUAL_JOINERS | PS), ('akhn', sm.F_GLOBAL_MANUAL_JOINERS | PS),
            ('rphf', sm.F_MANUAL_JOINERS | PS), ('rkrf', sm.F_GLOBAL_MANUAL_JOINERS | PS),
            ('pref', sm.F_MANUAL_JOINERS | PS), ('blwf', sm.F_MANUAL_JOINERS | PS),
            ('abvf', sm.F_MANUAL_JOINERS | PS), ('half', sm.F_MANUAL_JOINERS | PS),
            ('pstf', sm.F_MANUAL_JOINERS | PS), ('vatu', sm.F_GLOBAL_MANUAL_JOINERS | PS),
            ('cjct', sm.F_GLOBAL_MANUAL_JOINERS | PS),
            ('init', sm.F_MANUAL_JOINERS | PS), ('pres', sm.F_GLOBAL_MANUAL_JOINERS | PS),
            ('abvs', sm.F_GLOBAL_MANUAL_JOINERS | PS), ('blws', sm.F_GLOBAL_MANUAL_JOINERS | PS),
            ('psts', sm.F_GLOBAL_MANUAL_JOINERS | PS), ('haln', sm.F_GLOBAL_MANUAL_JOINERS | PS)]
BASIC = 11

# general categories after which a pre-base matra is not word-initial (Cf .. Mn in HarfBuzz's order)
NOT_INIT_AFTER = {'Cf', 'Cn', 'Co', 'Cs', 'Ll', 'Lm', 'Lo', 'Lt', 'Lu', 'Mc', 'Me', 'Mn'}


def ligated(info):
    return bool(info.props & sm.LIGATED)


def ligated_and_didnt_multiply(info):
    return bool(info.props & sm.LIGATED) and not (info.props & sm.MULTIPLIED)


def is_one_of(info, flags):
    if ligated(info):
        return False
    return bool(flag(info.cat) & flags)


def is_consonant(info):
    return is_one_of(info, CONSONANT_FLAGS)


def is_joiner(info):
    return is_one_of(info, JOINER_FLAGS)


def is_halant(info):
    return is_one_of(info, flag(H))


def syllables(b):
    start, n = 0, len(b.info)
    while start < n:
        end = start + 1
        while end < n and b.info[end].syllable == b.info[start].syllable:
            end += 1
        yield start, end
        start = end


class IndicShaper:
    zero_width_marks = 'none'
    no_short_circuit = True

    def __init__(self, script):
        self.script = script
        self.has_old_spec, self.virama, self.reph_pos, self.reph_mode, self.blwf_mode = CONFIGS[script]
        self.has_broken = False

    # --- the plan
    def collect_features(self, mb):
        mb.add_gsub_pause(self.setup_syllables)
        mb.enable_feature('locl', PS)
        mb.enable_feature('ccmp', PS)
        mb.add_gsub_pause(self.initial_reordering)
        for tag, flags in FEATURES[:BASIC]:
            mb.add_feature(tag, flags)
            mb.add_gsub_pause(None)
        mb.add_gsub_pause(self.final_reordering)
        for tag, flags in FEATURES[BASIC:]:
            mb.add_feature(tag, flags)

    def override_features(self, mb):
        mb.disable_feature('liga')
        mb.add_gsub_pause(None)

    def data_create(self, m, font):
        self.font = font
        chosen = m.chosen_script[0]
        self.is_old_spec = self.has_old_spec and not (isinstance(chosen, str) and chosen[3] == '2')
        self.virama_glyph = None
        self.zero_context = not self.is_old_spec and self.script != 'Mlym'
        self.lookups = {tag: m.stage_lookups(0, tag) for tag in ('rphf', 'pref', 'blwf', 'pstf', 'vatu')}
        self.mask = {tag: 0 if flags & sm.F_GLOBAL else m.get_1_mask(tag) for tag, flags in FEATURES}

    def would_substitute(self, tag, glyphs):
        names = [self.font.order[g] for g in glyphs]
        return any(sm.would_apply(self.font, lk.index, names, self.zero_context) for lk in self.lookups[tag])

    def load_virama_glyph(self):
        if self.virama_glyph is None:
            g = self.font.nominal(self.virama) if self.virama else None
            self.virama_glyph = g or 0
        return self.virama_glyph

    # --- before normalization
    def preprocess_text(self, b, font):
        """Vowel constraints: a dotted circle where a vowel and a sign would read as another vowel."""
        b.clear_output()
        count = len(b.info)
        if self.script == 'Deva':
            b.idx = 0
            while b.idx + 1 < count:
                matched = False
                u, nxt = b.cur().cp, b.info[b.idx + 1].cp
                if u == 0x0905:
                    matched = nxt in (0x093A, 0x093B, 0x093E, 0x0945, 0x0946, 0x0949, 0x094A, 0x094B, 0x094C,
                                      0x094F, 0x0956, 0x0957)
                elif u == 0x0906:
                    matched = nxt in (0x093A, 0x0945, 0x0946, 0x0947, 0x0948)
                elif u == 0x0909:
                    matched = nxt == 0x0941
                elif u == 0x090F:
                    matched = nxt in (0x0945, 0x0946, 0x0947)
                elif u == 0x0930:
                    if nxt == 0x094D and b.idx + 2 < count and b.info[b.idx + 2].cp == 0x0907:
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
        if ab in (0x0931, 0x09DC, 0x09DD, 0x0B94):
            return None
        return sm.decompose2(ab)

    def compose(self, a, b):
        if sm.is_mark_gc(sm.gc(a)):
            return None
        if (a, b) == (0x09AF, 0x09BC):
            return 0x09DF
        return sm.compose(a, b)

    def setup_masks(self, b, font):
        for inf in b.info:
            inf.cat, inf.pos = TABLE.get(inf.cp, (X, END))

    # --- pauses
    def setup_syllables(self, b):
        serial = 1
        for start, end, typ in syl.scan(MACHINE, [inf.cat for inf in b.info]):
            for i in range(start, end):
                b.info[i].syllable = (serial << 4) | typ
            serial += 1
            if serial == 16:
                serial = 1
            if typ == BROKEN_CLUSTER:
                self.has_broken = True

    def update_consonant_positions(self, b):
        virama = self.load_virama_glyph()
        if not virama:
            return
        for inf in b.info:
            if inf.pos == BASE_C:
                inf.pos = self.consonant_position(inf.glyph, virama)

    def consonant_position(self, consonant, virama):
        g = [virama, consonant, virama]
        if self.would_substitute('blwf', g[0:2]) or self.would_substitute('blwf', g[1:3]) or \
                self.would_substitute('vatu', g[0:2]) or self.would_substitute('vatu', g[1:3]):
            return BELOW_C
        if self.would_substitute('pstf', g[0:2]) or self.would_substitute('pstf', g[1:3]):
            return POST_C
        if self.would_substitute('pref', g[0:2]) or self.would_substitute('pref', g[1:3]):
            return POST_C
        return BASE_C

    def insert_dotted_circles(self, b):
        if not self.has_broken:
            return
        g = self.font.nominal(0x25CC)
        if g is None:
            return
        b.clear_output()
        b.idx = 0
        last = 0
        while b.idx < len(b.info):
            s = b.cur().syllable
            if last != s and (s & 0x0F) == BROKEN_CLUSTER:
                last = s
                cur = b.cur()
                dc = sm.Info.__new__(sm.Info)
                for f in sm.Info.__slots__:
                    setattr(dc, f, 0)
                dc.cp, dc.glyph, dc.cluster, dc.mask, dc.syllable = 0x25CC, g, cur.cluster, cur.mask, s
                dc.gc = 'Cc'
                dc.ign = dc.zwj = dc.zwnj = dc.hidden = dc.cont = False
                dc._name = None
                dc.cat, dc.pos = DOTTEDCIRCLE, END
                while b.idx < len(b.info) and last == b.cur().syllable and b.cur().cat == REPHA:
                    b.next_glyph()
                b.output_info(dc)
            else:
                b.next_glyph()
        b.sync()

    def initial_reordering(self, b):
        self.update_consonant_positions(b)
        self.insert_dotted_circles(b)
        for start, end in list(syllables(b)):
            if (b.info[start].syllable & 0x0F) in (CONSONANT_SYLLABLE, VOWEL_SYLLABLE, BROKEN_CLUSTER,
                                                   STANDALONE_CLUSTER):
                self.initial_reordering_consonant_syllable(b, start, end)

    def initial_reordering_consonant_syllable(self, b, start, end):
        info = b.info
        mask = self.mask
        base = end
        has_reph = False
        # the base consonant, and whether the syllable starts with a reph
        limit = start
        if mask['rphf'] and start + 3 <= end and (
                (self.reph_mode == REPH_IMPLICIT and not is_joiner(info[start + 2])) or
                (self.reph_mode == REPH_EXPLICIT and info[start + 2].cat == ZWJ)):
            g = [info[start].glyph, info[start + 1].glyph,
                 info[start + 2].glyph if self.reph_mode == REPH_EXPLICIT else 0]
            if self.would_substitute('rphf', g[:2]) or \
                    (self.reph_mode == REPH_EXPLICIT and self.would_substitute('rphf', g[:3])):
                limit += 2
                while limit < end and is_joiner(info[limit]):
                    limit += 1
                base = start
                has_reph = True
        elif self.reph_mode == REPH_LOG_REPHA and info[start].cat == REPHA:
            limit += 1
            while limit < end and is_joiner(info[limit]):
                limit += 1
            base = start
            has_reph = True
        i = end
        seen_below = False
        while True:
            i -= 1
            if is_consonant(info[i]):
                if info[i].pos != BELOW_C and (info[i].pos != POST_C or seen_below):
                    base = i
                    break
                if info[i].pos == BELOW_C:
                    seen_below = True
                base = i
            elif start < i and info[i].cat == ZWJ and info[i - 1].cat == H:
                break
            if not i > limit:
                break
        if has_reph and base == start and limit - base <= 2:
            has_reph = False
        # positions
        for i in range(start, base):
            info[i].pos = min(PRE_C, info[i].pos)
        if base < end:
            info[base].pos = BASE_C
        if has_reph:
            info[start].pos = RA_TO_BECOME_REPH
        if self.is_old_spec:
            disallow_double_halants = self.script == 'Knda'
            for i in range(base + 1, end):
                if info[i].cat == H:
                    j = end - 1
                    while j > i:
                        if is_consonant(info[j]) or (disallow_double_halants and info[j].cat == H):
                            break
                        j -= 1
                    if info[j].cat != H and j > i:
                        t = info.pop(i)
                        info.insert(j, t)
                    break
        # marks and joiners go with what is before them
        last_pos = START
        for i in range(start, end):
            if flag(info[i].cat) & (JOINER_FLAGS | flag(N) | flag(RS) | flag(CM) | flag(H)):
                info[i].pos = last_pos
                if info[i].cat == H and info[i].pos == PRE_M:
                    for j in range(i, start, -1):
                        if info[j - 1].pos != PRE_M:
                            info[i].pos = info[j - 1].pos
                            break
            elif info[i].pos != SMVD:
                if info[i].cat == MPST and i > start and info[i - 1].cat == SM:
                    info[i - 1].pos = info[i].pos
                last_pos = info[i].pos
        # what follows the base belongs to the next consonant
        last = base
        for i in range(base + 1, end):
            if is_consonant(info[i]):
                for j in range(last + 1, i):
                    if info[j].pos < SMVD:
                        info[j].pos = info[i].pos
                last = i
            elif flag(info[i].cat) & MATRA_FLAGS:
                last = i
        # sort by position
        syllable = info[start].syllable
        for i in range(start, end):
            info[i].syllable = i - start
        info[start:end] = sorted(info[start:end], key=lambda inf: inf.pos)
        first_left_matra = last_left_matra = end
        base = end
        for i in range(start, end):
            if info[i].pos == BASE_C:
                base = i
                break
            if info[i].pos == PRE_M:
                if first_left_matra == end:
                    first_left_matra = i
                last_left_matra = i
        if first_left_matra < last_left_matra:
            info[first_left_matra:last_left_matra + 1] = info[first_left_matra:last_left_matra + 1][::-1]
            i = first_left_matra
            for j in range(i, last_left_matra + 1):
                if flag(info[j].cat) & MATRA_FLAGS:
                    info[i:j + 1] = info[i:j + 1][::-1]
                    i = j + 1
        if self.is_old_spec or end - start > 127:
            b.merge_clusters(base, end)
        else:
            for i in range(base, end):
                if info[i].syllable != 255:
                    lo = hi = i
                    j = start + info[i].syllable
                    while j != i:
                        lo, hi = min(lo, j), max(hi, j)
                        nxt = start + info[j].syllable
                        info[j].syllable = 255
                        j = nxt
                    b.merge_clusters(max(base, lo), hi + 1)
        for i in range(start, end):
            info[i].syllable = syllable
        # masks
        for i in range(start, end):
            if info[i].pos != RA_TO_BECOME_REPH:
                break
            info[i].mask |= mask['rphf']
        m = mask['half']
        if not self.is_old_spec and self.blwf_mode == BLWF_PRE_AND_POST:
            m |= mask['blwf']
        for i in range(start, base):
            info[i].mask |= m
        m = mask['blwf'] | mask['abvf'] | mask['pstf']
        for i in range(base + 1, end):
            info[i].mask |= m
        if self.is_old_spec and self.script == 'Deva':
            for i in range(start, base - 1):
                if info[i].cat == RA and info[i + 1].cat == H and (i + 2 == base or info[i + 2].cat != ZWJ):
                    info[i].mask |= mask['blwf']
                    info[i + 1].mask |= mask['blwf']
        if mask['pref'] and base + 2 < end:
            for i in range(base + 1, end - 1):
                if self.would_substitute('pref', [info[i].glyph, info[i + 1].glyph]):
                    info[i].mask |= mask['pref']
                    info[i + 1].mask |= mask['pref']
                    break
        for i in range(start + 1, end):
            if is_joiner(info[i]):
                non_joiner = info[i].cat == ZWNJ
                j = i
                while True:
                    j -= 1
                    if non_joiner:
                        info[j].mask &= ~mask['half']
                    if not (j > start and not is_consonant(info[j])):
                        break

    def final_reordering(self, b):
        if not b.info:
            return
        for start, end in list(syllables(b)):
            self.final_reordering_syllable(b, start, end)

    def final_reordering_syllable(self, b, start, end):
        info = b.info
        mask = self.mask
        if self.virama_glyph:
            for i in range(start, end):
                if info[i].glyph == self.virama_glyph and ligated(info[i]) and info[i].props & sm.MULTIPLIED:
                    info[i].cat = H
                    info[i].props &= ~(sm.LIGATED | sm.MULTIPLIED)
        # the base again
        try_pref = bool(mask['pref'])
        base = start
        while base < end:
            if info[base].pos >= BASE_C:
                if try_pref and base + 1 < end:
                    for i in range(base + 1, end):
                        if info[i].mask & mask['pref']:
                            if not (info[i].props & sm.SUBSTITUTED and ligated_and_didnt_multiply(info[i])):
                                base = i
                                while base < end and is_halant(info[base]):
                                    base += 1
                                if base < end:
                                    info[base].pos = BASE_C
                                try_pref = False
                            break
                    if base == end:
                        break
                if self.script == 'Mlym':
                    i = base + 1
                    while i < end:
                        while i < end and is_joiner(info[i]):
                            i += 1
                        if i == end or not is_halant(info[i]):
                            break
                        i += 1
                        while i < end and is_joiner(info[i]):
                            i += 1
                        if i < end and is_consonant(info[i]) and info[i].pos == BELOW_C:
                            base = i
                            info[base].pos = BASE_C
                        i += 1
                if start < base and info[base].pos > BASE_C:
                    base -= 1
                break
            base += 1
        if base == end and start < base and is_one_of(info[base - 1], flag(ZWJ)):
            base -= 1
        if base < end:
            while start < base and is_one_of(info[base], flag(N) | flag(H)):
                base -= 1
        # a pre-base matra goes before the base (after a halant left of it)
        if start + 1 < end and start < base:
            new_pos = base - 2 if base == end else base - 1
            if self.script not in ('Mlym', 'Taml'):
                while True:
                    while new_pos > start and not is_one_of(info[new_pos], MATRA_FLAGS | flag(H)):
                        new_pos -= 1
                    if is_halant(info[new_pos]) and info[new_pos].pos != PRE_M:
                        if new_pos + 1 < end and info[new_pos + 1].cat == ZWJ and new_pos > start:
                            new_pos -= 1
                            continue
                    else:
                        new_pos = start
                    break
            if start < new_pos and info[new_pos].pos != PRE_M:
                i = new_pos
                while i > start:
                    if info[i - 1].pos == PRE_M:
                        old_pos = i - 1
                        if old_pos < base <= new_pos:
                            base -= 1
                        t = info.pop(old_pos)
                        info.insert(new_pos, t)
                        b.merge_clusters(new_pos, min(end, base + 1))
                        new_pos -= 1
                    i -= 1
            else:
                for i in range(start, base):
                    if info[i].pos == PRE_M:
                        b.merge_clusters(i, min(end, base + 1))
                        break
        # reph
        if start + 1 < end and info[start].pos == RA_TO_BECOME_REPH and \
                ((info[start].cat == REPHA) ^ ligated_and_didnt_multiply(info[start])):
            new_reph_pos = None
            if self.reph_pos != AFTER_POST:
                new_reph_pos = self.reph_after_halant(info, start, base)
                if new_reph_pos is None and self.reph_pos == AFTER_MAIN:
                    p = base
                    while p + 1 < end and info[p + 1].pos <= AFTER_MAIN:
                        p += 1
                    if p < end:
                        new_reph_pos = p
                if new_reph_pos is None and self.reph_pos == AFTER_SUB:
                    p = base
                    while p + 1 < end and not (flag(info[p + 1].pos) & (flag(POST_C) | flag(AFTER_POST) |
                                                                          flag(SMVD))):
                        p += 1
                    if p < end:
                        new_reph_pos = p
            if new_reph_pos is None:
                new_reph_pos = self.reph_after_halant(info, start, base)
            if new_reph_pos is None:
                p = end - 1
                while p > start and info[p].pos == SMVD:
                    p -= 1
                if is_halant(info[p]):
                    i = base + 1
                    while i < p:
                        if flag(info[i].cat) & MATRA_FLAGS:
                            p -= 1
                        i += 1
                new_reph_pos = p
            b.merge_clusters(start, new_reph_pos + 1)
            reph = info.pop(start)
            info.insert(new_reph_pos, reph)
            if start < base <= new_reph_pos:
                base -= 1
        # a pre-base reordering consonant (pref) goes before the base
        if try_pref and base + 1 < end:
            for i in range(base + 1, end):
                if info[i].mask & mask['pref']:
                    if ligated_and_didnt_multiply(info[i]):
                        new_pos = base
                        if self.script not in ('Mlym', 'Taml'):
                            while new_pos > start and not is_one_of(info[new_pos - 1], MATRA_FLAGS | flag(H)):
                                new_pos -= 1
                        if new_pos > start and is_halant(info[new_pos - 1]):
                            if new_pos < end and is_joiner(info[new_pos]):
                                new_pos += 1
                        old_pos = i
                        b.merge_clusters(new_pos, old_pos + 1)
                        t = info.pop(old_pos)
                        info.insert(new_pos, t)
                        if new_pos <= base < old_pos:
                            base += 1
                    break
        # a word-initial pre-base matra takes init
        if info[start].pos == PRE_M:
            if not start or info[start - 1].gc not in NOT_INIT_AFTER:
                info[start].mask |= mask['init']

    @staticmethod
    def reph_after_halant(info, start, base):
        """Reph steps 2 and 5: after the first halant before the base (and a joiner after it)."""
        p = start + 1
        while p < base and not is_halant(info[p]):
            p += 1
        if p < base and is_halant(info[p]):
            if p + 1 < base and is_joiner(info[p + 1]):
                p += 1
            return p
        return None

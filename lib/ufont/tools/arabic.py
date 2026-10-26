#!/usr/bin/env python3
"""Models of lib/ufont's Arabic and Hebrew shapers, used by tools/shapemodel.py.

Arabic (and Syriac), as HarfBuzz's Arabic shaper:

- each character's joining type (Unicode's ArabicShaping, tools/ucd_data.py;
  unlisted marks and format characters transparent) runs a joining state
  machine that gives every joining character its form - isolated, final,
  medial, initial, and Syriac's fin2, fin3, med2 - as a feature mask;
- the plan: stch, then ccmp / locl, the form features one stage each, then
  rlig, calt, liga, clig, mset - ZWJ not skipped by them (it breaks
  ligatures in Arabic);
- modifier combining marks (hamza above, small high seen, ...) are moved
  before the other marks of their class, as Unicode's TR53 asks;
- mark widths zeroed from GDEF after positioning.

A font without Arabic GSUB features gets HarfBuzz's fallback: single
substitutions to the presentation forms the font maps (init, medi, fina,
isol) and ligatures between them (lam-alef and others, shadda with a
haraka), synthesized and applied after rlig. The stch stretching feature is
not modelled; a font with it raises.

Hebrew, as HarfBuzz's Hebrew shaper: presentation forms composed for old
fonts with no mark positioning; patah / qamats then sheva / hiriq then
meteg or a below mark reordered; GPOS only from a font's 'hebr' script.

Development-machine tooling only; not part of any OS image.
"""
import shapemodel as sm
from ucd_data import JOINING, ARABIC_FORMS, ARABIC_LIG2, ARABIC_LIG3, ARABIC_LIGM

# joining types
JT_U, JT_L, JT_R, JT_D, ALAPH, DALATH_RISH, JT_T = 0, 1, 2, 3, 4, 5, 7
ISOL, FINA, FIN2, FIN3, MEDI, MED2, INIT, NONE = range(8)
FEATURES = ['isol', 'fina', 'fin2', 'fin3', 'medi', 'med2', 'init']

# (prev action, current action, next state) per state and joining type
STATES = [
    [(NONE, NONE, 0), (NONE, ISOL, 2), (NONE, ISOL, 1), (NONE, ISOL, 2), (NONE, ISOL, 1), (NONE, ISOL, 6)],
    [(NONE, NONE, 0), (NONE, ISOL, 2), (NONE, ISOL, 1), (NONE, ISOL, 2), (NONE, FIN2, 5), (NONE, ISOL, 6)],
    [(NONE, NONE, 0), (NONE, ISOL, 2), (INIT, FINA, 1), (INIT, FINA, 3), (INIT, FINA, 4), (INIT, FINA, 6)],
    [(NONE, NONE, 0), (NONE, ISOL, 2), (MEDI, FINA, 1), (MEDI, FINA, 3), (MEDI, FINA, 4), (MEDI, FINA, 6)],
    [(NONE, NONE, 0), (NONE, ISOL, 2), (MED2, ISOL, 1), (MED2, ISOL, 2), (MED2, FIN2, 5), (MED2, ISOL, 6)],
    [(NONE, NONE, 0), (NONE, ISOL, 2), (ISOL, ISOL, 1), (ISOL, ISOL, 2), (ISOL, FIN2, 5), (ISOL, ISOL, 6)],
    [(NONE, NONE, 0), (NONE, ISOL, 2), (NONE, ISOL, 1), (NONE, ISOL, 2), (NONE, FIN3, 5), (NONE, ISOL, 6)],
]

# Unicode TR53 modifier combining marks
MCM = {0x0654, 0x0655, 0x0658, 0x06DC, 0x06E3, 0x06E7, 0x06E8, 0x08CA, 0x08CB, 0x08CD, 0x08CE, 0x08CF, 0x08D3,
       0x08F3}


def joining_type(cp, gc):
    t = JOINING.get(cp)
    if t is not None:
        return t
    return JT_T if gc in ('Mn', 'Me', 'Cf') else JT_U


def syriac(tag):
    return tag[3] in '23'


class _Lookup:
    """A synthesized GSUB lookup, shaped like fontTools' for shapemodel's apply code."""

    def __init__(self, kind, flag, sub):
        self.LookupType, self.LookupFlag, self.SubTable = kind, flag, [sub]


class _Single:
    def __init__(self, mapping):
        self.mapping = mapping


class _Lig:
    def __init__(self, components, glyph):
        self.Component, self.LigGlyph = components, glyph


class _Ligatures:
    def __init__(self, ligatures):
        self.ligatures = ligatures


def fallback_single(font, k):
    pairs = []
    for u in range(min(ARABIC_FORMS), max(ARABIC_FORMS) + 1):
        s = ARABIC_FORMS.get(u, (0, 0, 0, 0))[k]
        if not s:
            continue
        ug, sg = font.nominal(u), font.nominal(s)
        if ug is None or sg is None or ug == sg or ug > 0xFFFF or sg > 0xFFFF:
            continue
        pairs.append((ug, sg))
    if not pairs:
        return None
    pairs.sort(key=lambda p: p[0])
    mapping = {}
    for ug, sg in pairs:
        mapping.setdefault(font.order[ug], font.order[sg])
    return _Lookup(1, 8, _Single(mapping))


def fallback_ligature(font, table, flag):
    firsts = []
    for f0 in table:
        g = font.nominal(f0)
        if g is not None:
            firsts.append((g, f0))
    firsts.sort(key=lambda p: p[0])
    ligs, any_lig = {}, False
    for g, f0 in firsts:
        for entry in table[f0]:
            *comps, lig = entry
            lg = font.nominal(lig)
            if lg is None:
                continue
            cg = [font.nominal(c) if c else None for c in comps]
            if any(x is None for x in cg):
                continue
            ligs.setdefault(font.order[g], []).append(_Lig([font.order[x] for x in cg], font.order[lg]))
            any_lig = True
    return _Lookup(4, flag, _Ligatures(ligs)) if any_lig else None


class ArabicShaper:
    zero_width_marks = 'late'
    no_short_circuit = False
    gpos_tag = None
    fallback_position = True

    def __init__(self, script):
        self.script = script

    def collect_features(self, mb):
        mb.enable_feature('stch')
        mb.add_gsub_pause(self.record_stch)
        mb.enable_feature('ccmp', sm.F_MANUAL_ZWJ)
        mb.enable_feature('locl', sm.F_MANUAL_ZWJ)
        mb.add_gsub_pause(None)
        for tag in FEATURES:
            fb = self.script == 'Arab' and not syriac(tag)
            mb.add_feature(tag, sm.F_MANUAL_ZWJ | (sm.F_HAS_FALLBACK if fb else 0))
            mb.add_gsub_pause(None)
        mb.add_gsub_pause(None)
        mb.enable_feature('rlig', sm.F_MANUAL_ZWJ | sm.F_HAS_FALLBACK)
        if self.script == 'Arab':
            mb.add_gsub_pause(self.fallback_shape)
        mb.enable_feature('calt', sm.F_MANUAL_ZWJ)
        if not any(f[0] == 'rclt' for f in mb.infos):
            mb.add_gsub_pause(None)
        mb.enable_feature('liga', sm.F_MANUAL_ZWJ)
        mb.enable_feature('clig', sm.F_MANUAL_ZWJ)
        mb.enable_feature('mset', sm.F_MANUAL_ZWJ)

    def override_features(self, mb):
        pass

    def data_create(self, m, font):
        self.masks = [m.get_1_mask(tag) for tag in FEATURES] + [0]
        if m.get_1_mask('stch'):
            raise NotImplementedError('the stch feature')
        fallback = self.script == 'Arab'
        for tag in FEATURES:
            f = m.features.get(tag)
            fallback = fallback and (syriac(tag) or (f is not None and f[3]))
        self.do_fallback = fallback
        self.font = font
        self.fallback = None
        if fallback:
            # init, medi, fina, isol forms; rlig: three-letter, two-letter and mark ligatures
            plan = [('init', fallback_single(font, 0)), ('medi', fallback_single(font, 1)),
                    ('fina', fallback_single(font, 2)), ('isol', fallback_single(font, 3)),
                    ('rlig', fallback_ligature(font, ARABIC_LIG3, 8)),
                    ('rlig', fallback_ligature(font, ARABIC_LIG2, 8)),
                    ('rlig', fallback_ligature(font, ARABIC_LIGM, 0))]
            self.fallback = [(m.get_1_mask(tag), lk) for tag, lk in plan if m.get_1_mask(tag) and lk]

    def record_stch(self, b):
        pass                                            # no stch in the plan (data_create)

    def fallback_shape(self, b):
        if not self.do_fallback or not self.fallback:
            return
        c = sm.Ctx(self.font, b, _Table(), False)
        for mask, lk in self.fallback:
            sm.apply_lookup(c, lk, mask)

    def preprocess_text(self, b, font):
        pass

    def decompose(self, ab):
        return sm.decompose2(ab)

    def compose(self, a, b):
        return sm.compose(a, b)

    def setup_masks(self, b, font):
        info = b.info
        prev, state = None, 0
        actions = [NONE] * len(info)
        for i, inf in enumerate(info):
            t = joining_type(inf.cp, inf.gc)
            if t == JT_T:
                actions[i] = NONE
                continue
            pa, ca, ns = STATES[state][t]
            if pa != NONE and prev is not None:
                actions[prev] = pa
            actions[i] = ca
            prev, state = i, ns
        for inf, a in zip(info, actions):
            inf.mask |= self.masks[a]

    def reorder_marks(self, b, start, end):
        """Modifier combining marks of class 220 / 230 go before the other marks of their class."""
        info = b.info
        i = start
        for cc in (220, 230):
            while i < end and info[i].mcc < cc:
                i += 1
            if i == end:
                break
            if info[i].mcc > cc:
                continue
            j = i
            while j < end and info[j].mcc == cc and info[j].cp in MCM:
                j += 1
            if i == j:
                continue
            b.merge_clusters(start, j)
            moved = info[i:j]
            info[start + j - i:j] = info[start:i]
            info[start:start + j - i] = moved
            new_start = start + j - i
            new_cc = 25 if cc == 220 else 26
            while start < new_start:
                info[start].mcc = new_cc
                start += 1
            i = j


class _Table:
    class LookupList:
        Lookup = []


DAGESH_FORMS = [0xFB30, 0xFB31, 0xFB32, 0xFB33, 0xFB34, 0xFB35, 0xFB36, 0, 0xFB38, 0xFB39, 0xFB3A, 0xFB3B, 0xFB3C,
                0, 0xFB3E, 0, 0xFB40, 0xFB41, 0, 0xFB43, 0xFB44, 0, 0xFB46, 0xFB47, 0xFB48, 0xFB49, 0xFB4A]


class HebrewShaper:
    zero_width_marks = 'late'
    no_short_circuit = False
    gpos_tag = 'hebr'
    fallback_position = True

    def __init__(self, script):
        self.script = script
        self.has_gpos_mark = True

    def collect_features(self, mb):
        pass

    def override_features(self, mb):
        pass

    def data_create(self, m, font):
        self.has_gpos_mark = bool(m.get_1_mask('mark'))

    def preprocess_text(self, b, font):
        pass

    def setup_masks(self, b, font):
        pass

    def decompose(self, ab):
        return sm.decompose2(ab)

    def compose(self, a, b):
        ab = sm.compose(a, b)
        if ab is not None or self.has_gpos_mark:
            return ab
        # presentation forms, for old fonts
        if b == 0x05B4 and a == 0x05D9:
            return 0xFB1D
        if b == 0x05B7:
            return {0x05F2: 0xFB1F, 0x05D0: 0xFB2E}.get(a)
        if b == 0x05B8 and a == 0x05D0:
            return 0xFB2F
        if b == 0x05B9 and a == 0x05D5:
            return 0xFB4B
        if b == 0x05BC:
            if 0x05D0 <= a <= 0x05EA:
                return DAGESH_FORMS[a - 0x05D0] or None
            return {0xFB2A: 0xFB2C, 0xFB2B: 0xFB2D}.get(a)
        if b == 0x05BF:
            return {0x05D1: 0xFB4C, 0x05DB: 0xFB4D, 0x05E4: 0xFB4E}.get(a)
        if b == 0x05C1:
            return {0x05E9: 0xFB2A, 0xFB49: 0xFB2C}.get(a)
        if b == 0x05C2:
            return {0x05E9: 0xFB2B, 0xFB49: 0xFB2D}.get(a)
        return None

    def reorder_marks(self, b, start, end):
        """Patah / qamats, then sheva / hiriq, then meteg or a below mark: the last two swap."""
        info = b.info
        for i in range(start + 2, end):
            c0, c1, c2 = info[i - 2].mcc, info[i - 1].mcc, info[i].mcc
            if c0 in (20, 21) and c1 in (22, 23) and c2 in (25, 220):
                b.merge_clusters(i - 1, i + 1)
                info[i - 1], info[i] = info[i], info[i - 1]
                break

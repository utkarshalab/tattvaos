#!/usr/bin/env python3
"""A model of lib/ufont's text shaping (layout/*.asm): OpenType GSUB / GPOS over a run.

    shape(font, codepoints, script=None, language=None) -> [(glyph, cluster, x_advance,
        y_advance, x_offset, y_offset)] in font units

It follows HarfBuzz's pipeline for the shapers ufont has - the default one (Latin,
Greek, Cyrillic and every script without a shaper of its own) and, in indic.py,
Devanagari - step for step, so the two agree glyph for glyph: Unicode properties,
grapheme clusters, normalization against the font (decompose, reorder marks,
recompose), the feature plan, GSUB (all eight lookup types), advances, GPOS (all
nine), mark widths, attachment offsets, default ignorables hidden.

Development-machine tooling only; not part of any OS image.
"""
import unicodedata

from fontTools import unicodedata as fud
from fontTools.ttLib import TTFont

# glyph props (GDEF classes, as HarfBuzz keeps them)
BASE, LIGATURE, MARK = 0x02, 0x04, 0x08
SUBSTITUTED, LIGATED, MULTIPLIED = 0x10, 0x20, 0x40
PRESERVE = SUBSTITUTED | LIGATED | MULTIPLIED
IGNORE_FLAGS = 0x0E
USE_MARK_FILTERING_SET = 0x10
MARK_ATTACHMENT_TYPE = 0xFF00
IS_LIG_BASE = 0x10
ATTACH_MARK, ATTACH_CURSIVE = 1, 2
MAX_NESTING = 64
MAX_CONTEXT = 64

# feature flags (HarfBuzz's map)
F_GLOBAL, F_HAS_FALLBACK, F_MANUAL_ZWNJ, F_MANUAL_ZWJ = 0x01, 0x02, 0x04, 0x08
F_MANUAL_JOINERS = F_MANUAL_ZWNJ | F_MANUAL_ZWJ
F_GLOBAL_MANUAL_JOINERS = F_GLOBAL | F_MANUAL_JOINERS
F_GLOBAL_HAS_FALLBACK = F_GLOBAL | F_HAS_FALLBACK
F_GLOBAL_SEARCH, F_RANDOM, F_PER_SYLLABLE = 0x10, 0x20, 0x40
MAX_VALUE = 255
GLOBAL_MASK = 1 << 31

COMMON = [('abvm', F_GLOBAL), ('blwm', F_GLOBAL), ('ccmp', F_GLOBAL), ('locl', F_GLOBAL),
          ('mark', F_GLOBAL_MANUAL_JOINERS), ('mkmk', F_GLOBAL_MANUAL_JOINERS), ('rlig', F_GLOBAL)]
HORIZONTAL = [('calt', F_GLOBAL), ('clig', F_GLOBAL), ('curs', F_GLOBAL), ('dist', F_GLOBAL),
              ('kern', F_GLOBAL_HAS_FALLBACK), ('liga', F_GLOBAL), ('rclt', F_GLOBAL)]
NO_SCRIPT = 0xFFFF


# ---------------------------------------------------------------- Unicode
def gc(cp):
    return unicodedata.category(chr(cp))


def is_mark_gc(cat):
    return cat in ('Mn', 'Mc', 'Me')


def is_default_ignorable(ch):
    plane = ch >> 16
    if plane == 0:
        page = ch >> 8
        if page == 0x00:
            return ch == 0x00AD
        if page == 0x03:
            return ch == 0x034F
        if page == 0x06:
            return ch == 0x061C
        if page == 0x17:
            return 0x17B4 <= ch <= 0x17B5
        if page == 0x18:
            return 0x180B <= ch <= 0x180E
        if page == 0x20:
            return 0x200B <= ch <= 0x200F or 0x202A <= ch <= 0x202E or 0x2060 <= ch <= 0x206F
        if page == 0xFE:
            return 0xFE00 <= ch <= 0xFE0F or ch == 0xFEFF
        if page == 0xFF:
            return 0xFFF0 <= ch <= 0xFFF8
        return False
    if plane == 0x01:
        return 0x1D173 <= ch <= 0x1D17A
    if plane == 0x0E:
        return 0xE0000 <= ch <= 0xE0FFF
    return False


def is_variation_selector(cp):
    return 0xFE00 <= cp <= 0xFE0F or 0xE0100 <= cp <= 0xE01EF or 0x180B <= cp <= 0x180D or cp == 0x180F


def ccc(cp):
    return unicodedata.combining(chr(cp))


def decompose2(ab):
    """HarfBuzz's canonical decomposition: ab -> (a, b) (b 0 for a singleton), or None."""
    d = unicodedata.decomposition(chr(ab))
    if not d or d.startswith('<'):
        return None
    parts = [int(x, 16) for x in d.split()]
    if len(parts) == 1:
        return parts[0], 0
    return parts[0], parts[1]


_COMPOSE = {}
for _cp in range(0x110000):
    _d = unicodedata.decomposition(chr(_cp))
    if _d and not _d.startswith('<'):
        _p = [int(x, 16) for x in _d.split()]
        if len(_p) == 2 and unicodedata.normalize('NFC', chr(_p[0]) + chr(_p[1])) == chr(_cp):
            _COMPOSE[(_p[0], _p[1])] = _cp


def compose(a, b):
    return _COMPOSE.get((a, b))


# space fallback (HarfBuzz's space_t): a width when the font lacks the space
SPACE_EM, SPACE_EM_2, SPACE_EM_3, SPACE_EM_4, SPACE_EM_5, SPACE_EM_6, SPACE_EM_16 = 1, 2, 3, 4, 5, 6, 16
SPACE_4_EM_18, SPACE, SPACE_FIGURE, SPACE_PUNCTUATION, SPACE_NARROW = 17, 18, 19, 20, 21
SPACE_TYPES = {0x20: SPACE, 0xA0: SPACE, 0x2000: SPACE_EM_2, 0x2001: SPACE_EM, 0x2002: SPACE_EM_2,
               0x2003: SPACE_EM, 0x2004: SPACE_EM_3, 0x2005: SPACE_EM_4, 0x2006: SPACE_EM_6,
               0x2007: SPACE_FIGURE, 0x2008: SPACE_PUNCTUATION, 0x2009: SPACE_EM_5, 0x200A: SPACE_EM_16,
               0x202F: SPACE_NARROW, 0x205F: SPACE_4_EM_18, 0x3000: SPACE_EM}


# OpenType script tags for Unicode scripts (HarfBuzz: the new Indic tags first)
SCRIPT_TAGS = {'Deva': ['dev2', 'deva'], 'Beng': ['bng2', 'beng'], 'Guru': ['gur2', 'guru'],
               'Gujr': ['gjr2', 'gujr'], 'Orya': ['ory2', 'orya'], 'Taml': ['tml2', 'taml'],
               'Telu': ['tel2', 'telu'], 'Knda': ['knd2', 'knda'], 'Mlym': ['mlm2', 'mlym'],
               'Mymr': ['mym2', 'mymr'], 'Hira': ['kana'], 'Kana': ['kana'], 'Laoo': ['lao '],
               'Yiii': ['yi  '], 'Nkoo': ['nko '], 'Vaii': ['vai ']}


def script_tags(script):
    if script is None or script in ('Zyyy', 'Zinh', 'Zzzz'):
        return []
    return SCRIPT_TAGS.get(script, [script.lower()])


def guess_script(cps):
    for cp in cps:
        s = fud.script(chr(cp))
        if s not in ('Zyyy', 'Zinh', 'Zzzz'):
            return s
    return None


# ---------------------------------------------------------------- buffer
class Info:
    __slots__ = ('cp', 'glyph', 'cluster', 'mask', 'props', 'gc', 'mcc', 'ign', 'zwj', 'zwnj', 'hidden',
                 'cont', 'lig', 'syllable', 'cat', 'pos', '_name', 'space')

    def __init__(self, cp, cluster):
        self.cp, self.glyph, self.cluster, self.mask = cp, 0, cluster, 1
        self.props, self.lig, self.syllable, self.cat, self.pos = 0, 0, 0, 0, 0
        self._name = None
        self.space = 0
        self.set_unicode(cp)

    def set_unicode(self, cp):
        cat = gc(cp)
        self.gc = cat
        self.ign = self.zwj = self.zwnj = self.hidden = False
        self.cont = False
        self.mcc = 0
        if cp >= 0x80:
            if is_default_ignorable(cp):
                self.ign = True
                if cp == 0x200C:
                    self.zwnj = True
                elif cp == 0x200D:
                    self.zwj = True
                elif 0x180B <= cp <= 0x180D or cp == 0x180F or 0xE0020 <= cp <= 0xE007F or cp == 0x034F:
                    self.hidden = True
            if is_mark_gc(cat):
                self.cont = True
                self.mcc = ccc(cp)

    def copy(self):
        n = Info.__new__(Info)
        for s in Info.__slots__:
            setattr(n, s, getattr(self, s))
        return n

    # ligature properties
    def lig_id(self):
        return self.lig >> 5

    def lig_comp(self):
        return 0 if self.lig & IS_LIG_BASE else self.lig & 0x0F

    def lig_num_comps(self):
        if (self.props & LIGATURE) and (self.lig & IS_LIG_BASE):
            return self.lig & 0x0F
        return 1

    def is_mark(self):
        return bool(self.props & MARK)

    def is_base(self):
        return bool(self.props & BASE)

    def is_ligature(self):
        return bool(self.props & LIGATURE)

    def multiplied(self):
        return bool(self.props & MULTIPLIED)

    def substituted(self):
        return bool(self.props & SUBSTITUTED)

    def is_default_ignorable(self):
        return self.ign and not self.substituted()

    def is_default_ignorable_and_not_hidden(self):
        return self.ign and not self.hidden and not self.substituted()


class Pos:
    __slots__ = ('xa', 'ya', 'xo', 'yo', 'chain', 'type')

    def __init__(self):
        self.xa = self.ya = self.xo = self.yo = self.chain = self.type = 0


class Buffer:
    def __init__(self, infos):
        self.info = infos
        self.out = []
        self.idx = 0
        self.have_output = False
        self.serial = 0
        self.pos = None

    # --- output buffer machinery (HarfBuzz's in / out arrays)
    def clear_output(self):
        self.out = []
        self.have_output = True

    def sync(self):
        self.out += self.info[self.idx:]
        self.info = self.out
        self.out = []
        self.have_output = False
        self.idx = 0

    def cur(self):
        return self.info[self.idx]

    def next_glyph(self):
        if self.have_output:
            self.out.append(self.info[self.idx])
        self.idx += 1

    def next_glyphs(self, n):
        for _ in range(n):
            self.next_glyph()

    def skip_glyph(self):
        self.idx += 1

    def replace_glyph(self, g):
        n = self.info[self.idx].copy()
        n.glyph = g
        self.out.append(n)
        self.idx += 1

    def output_glyph(self, g):
        n = self.info[self.idx].copy()
        n.glyph = g
        self.out.append(n)

    def output_info(self, n):
        self.out.append(n)

    def delete_glyph(self):
        cluster = self.info[self.idx].cluster
        if self.idx + 1 < len(self.info) and cluster == self.info[self.idx + 1].cluster:
            self.idx += 1
            return
        if self.out:
            if cluster < self.out[-1].cluster:
                mask = self.info[self.idx].mask
                old = self.out[-1].cluster
                i = len(self.out)
                while i and self.out[i - 1].cluster == old:
                    self.out[i - 1].cluster = cluster
                    i -= 1
            self.idx += 1
            return
        if self.idx + 1 < len(self.info):
            self.merge_clusters(self.idx, self.idx + 2)
        self.idx += 1

    def next_serial(self):
        self.serial = (self.serial + 1) & 0xFF
        if self.serial == 0:
            self.serial = 1
        return self.serial

    def backtrack_len(self):
        return len(self.out) if self.have_output else self.idx

    def lookahead_len(self):
        return len(self.info) - self.idx

    def move_to(self, i):
        if not self.have_output:
            self.idx = i
            return True
        if i > len(self.out):
            count = i - len(self.out)
            self.out += self.info[self.idx:self.idx + count]
            self.idx += count
        elif i < len(self.out):
            count = len(self.out) - i
            self.idx -= count
            self.info[self.idx:self.idx + count] = self.out[i:]
            del self.out[i:]
        return True

    # --- clusters (cluster level 0: monotone graphemes)
    def merge_clusters(self, start, end):
        if end - start < 2:
            return
        info = self.info
        cluster = min(info[i].cluster for i in range(start, end))
        while end < len(info) and info[end - 1].cluster == info[end].cluster:
            end += 1
        while start and info[start - 1].cluster == info[start].cluster:
            start -= 1
        if self.have_output and start == 0 or (self.have_output and start == self.idx):
            pass
        if self.have_output and start <= self.idx:
            # the part already moved to out
            i = len(self.out)
            while i and self.out[i - 1].cluster == info[start].cluster:
                self.out[i - 1].cluster = cluster
                i -= 1
        for i in range(start, end):
            info[i].cluster = cluster

    def merge_out_clusters(self, start, end):
        if end - start < 2:
            return
        out = self.out
        cluster = min(out[i].cluster for i in range(start, end))
        while start and out[start - 1].cluster == out[start].cluster:
            start -= 1
        while end < len(out) and out[end - 1].cluster == out[end].cluster:
            end += 1
        if end == len(out):
            i = self.idx
            while i < len(self.info) and self.info[i].cluster == out[end - 1].cluster:
                self.info[i].cluster = cluster
                i += 1
        for i in range(start, end):
            out[i].cluster = cluster

    def sort(self, start, end, key):
        for i in range(start + 1, end):
            j = i
            while j > start and key(self.info[j - 1]) > key(self.info[i]):
                j -= 1
            if i == j:
                continue
            self.merge_clusters(j, i + 1)
            t = self.info[i]
            del self.info[i]
            self.info.insert(j, t)


# ---------------------------------------------------------------- font
class Font:
    def __init__(self, path):
        self.tt = TTFont(path)
        self.order = self.tt.getGlyphOrder()
        self.gid = {n: i for i, n in enumerate(self.order)}
        cmap = None
        for t in self.tt['cmap'].tables:
            uni = t.platformID == 0 or (t.platformID == 3 and t.platEncID in (1, 10))
            if uni and t.format == 12 and (cmap is None or cmap.format != 12):
                cmap = t
            elif uni and t.format == 4 and cmap is None:
                cmap = t
        self.cmap = cmap.cmap
        self.uvs = {}
        for t in self.tt['cmap'].tables:
            if t.format == 14:
                for vs, pairs in t.uvsDict.items():
                    for u, gname in pairs:
                        self.uvs[(u, vs)] = gname
        self.hmtx = self.tt['hmtx']
        gdef = self.tt['GDEF'].table if 'GDEF' in self.tt else None
        self.classdef = gdef.GlyphClassDef.classDefs if gdef and gdef.GlyphClassDef else None
        self.markattach = gdef.MarkAttachClassDef.classDefs if gdef and gdef.MarkAttachClassDef else {}
        self.marksets = [set(c.glyphs) for c in gdef.MarkGlyphSetsDef.Coverage] \
            if gdef and getattr(gdef, 'MarkGlyphSetsDef', None) else []
        self.kern = []
        if 'kern' in self.tt and getattr(self.tt['kern'], 'version', 1) == 0:
            for st in self.tt['kern'].kernTables:
                # horizontal, not cross-stream, not variation, format 0
                if getattr(st, 'format', None) == 0 and (st.coverage & 1) and not (st.coverage & 0x0C):
                    self.kern.append({(self.gid[a], self.gid[b_]): v for (a, b_), v in st.kernTable.items()})
        self.gsub = self.tt['GSUB'].table if 'GSUB' in self.tt else None
        self.gpos = self.tt['GPOS'].table if 'GPOS' in self.tt else None

    def variation(self, u, vs):
        if (u, vs) not in self.uvs:
            return None
        gname = self.uvs[(u, vs)]
        return self.nominal(u) if gname is None else self.gid[gname]

    def nominal(self, cp):
        n = self.cmap.get(cp)
        return None if n is None else self.gid[n]

    def advance(self, g):
        return self.hmtx[self.order[g]][0]

    def glyph_props(self, g):
        if self.classdef is None:
            return 0
        k = self.classdef.get(self.order[g], 0)
        if k == 1:
            return BASE
        if k == 2:
            return LIGATURE
        if k == 3:
            return MARK | (self.markattach.get(self.order[g], 0) << 8)
        return 0

    def mark_set_covers(self, s, g):
        return s < len(self.marksets) and self.order[g] in self.marksets[s]


# ---------------------------------------------------------------- the plan
def select_script(table, tags):
    """HarfBuzz's script choice: the tags, else DFLT, dflt, latn -> ScriptRecord or None."""
    if table is None:
        return None
    recs = {r.ScriptTag: r for r in table.ScriptList.ScriptRecord}
    for t in tags + ['DFLT', 'dflt', 'latn']:
        if t in recs:
            return recs[t]
    return None


def langsys(srec, language):
    if srec is None:
        return None
    if language:
        for lr in srec.Script.LangSysRecord:
            if lr.LangSysTag == language:
                return lr.LangSys
    return srec.Script.DefaultLangSys


class Lookup:
    __slots__ = ('index', 'mask', 'auto_zwnj', 'auto_zwj', 'random', 'per_syllable')

    def __init__(self, index, mask, auto_zwnj=True, auto_zwj=True, random=False, per_syllable=False):
        self.index, self.mask, self.auto_zwnj, self.auto_zwj = index, mask, auto_zwnj, auto_zwj
        self.random, self.per_syllable = random, per_syllable


class Map:
    """A compiled plan: feature masks, and per table the lookups with the stages they fall in."""

    def __init__(self):
        self.global_mask = GLOBAL_MASK
        self.features = {}                          # tag -> (mask, 1 mask, stages)
        self.lookups = [[], []]                     # GSUB, GPOS: [Lookup]
        self.stages = [[], []]                      # [(last lookup, pause function or None)]
        self.chosen_script = [NO_SCRIPT, NO_SCRIPT]

    def get_1_mask(self, tag):
        f = self.features.get(tag)
        return f[1] if f else 0

    def get_mask(self, tag):
        f = self.features.get(tag)
        return f[0] if f else 0

    def stage_lookups(self, t, tag):
        """The lookups of the stage a feature is in (HarfBuzz's get_stage_lookups)."""
        f = self.features.get(tag)
        stage = f[2][t] if f else 1 << 32
        if stage > len(self.stages[t]):
            return []
        start = self.stages[t][stage - 1][0] if stage else 0
        end = self.stages[t][stage][0] if stage < len(self.stages[t]) else len(self.lookups[t])
        return self.lookups[t][start:end]


class MapBuilder:
    """HarfBuzz's map builder: features and pauses as the shaper adds them, then compiled
    against the font's chosen script and language systems."""

    def __init__(self):
        self.infos = []                             # [tag, seq, max, flags, default, stage gsub, stage gpos]
        self.current = [0, 0]
        self.pauses = [[], []]                      # [(stage, function)]

    def add_feature(self, tag, flags=0, value=1):
        self.infos.append([tag, len(self.infos) + 1, value, flags, value if flags & F_GLOBAL else 0,
                           self.current[0], self.current[1]])

    def enable_feature(self, tag, flags=0, value=1):
        self.add_feature(tag, F_GLOBAL | flags, value)

    def disable_feature(self, tag):
        self.add_feature(tag, F_GLOBAL, 0)

    def add_pause(self, t, func):
        self.pauses[t].append((self.current[t], func))
        self.current[t] += 1

    def add_gsub_pause(self, func):
        self.add_pause(0, func)

    def compile(self, tables, scripts, langsyss):
        m = Map()
        for t in range(2):
            if scripts[t] is not None:
                m.chosen_script[t] = scripts[t].ScriptTag
        req = []
        for t in range(2):
            ls = langsyss[t]
            if ls is not None and ls.ReqFeatureIndex != 0xFFFF:
                req.append((ls.ReqFeatureIndex, tables[t].FeatureList.FeatureRecord[ls.ReqFeatureIndex].FeatureTag))
            else:
                req.append((None, None))
        req_stage = [0, 0]
        infos = sorted(self.infos, key=lambda f: (f[0].encode('latin-1'), f[1]))
        merged = []
        for f in infos:
            if merged and merged[-1][0] == f[0]:
                j = merged[-1]
                if f[3] & F_GLOBAL:
                    j[3] |= F_GLOBAL
                    j[2], j[4] = f[2], f[4]
                else:
                    j[3] &= ~F_GLOBAL
                    j[2] = max(j[2], f[2])
                j[3] |= f[3] & F_HAS_FALLBACK
                j[5], j[6] = min(j[5], f[5]), min(j[6], f[6])
            else:
                merged.append(list(f))
        indices = [{}, {}]
        for t in range(2):
            ls = langsyss[t]
            if ls is None:
                continue
            for fi in ls.FeatureIndex:
                indices[t].setdefault(tables[t].FeatureList.FeatureRecord[fi].FeatureTag, fi)
        next_bit = 4
        feats = []
        for tag, _, maxv, flags, default, s0, s1 in merged:
            if flags & F_GLOBAL and maxv == 1:
                bits = 0
            else:
                bits = min(8, maxv.bit_length())
            if not maxv or next_bit + bits >= 31:
                continue
            found = False
            index = [None, None]
            for t in range(2):
                if req[t][1] == tag:
                    req_stage[t] = (s0, s1)[t]
                if tag in indices[t]:
                    index[t] = indices[t][tag]
                    found = True
            if not found and not (flags & F_HAS_FALLBACK):
                continue
            if flags & F_GLOBAL and maxv == 1:
                shift, mask = 31, GLOBAL_MASK
            else:
                shift, mask = next_bit, (1 << (next_bit + bits)) - (1 << next_bit)
                next_bit += bits
                m.global_mask |= (default << shift) & mask
            m.features[tag] = (mask, (1 << shift) & mask, (s0, s1))
            feats.append((tag, index, (s0, s1), mask, not (flags & F_MANUAL_ZWNJ), not (flags & F_MANUAL_ZWJ),
                          bool(flags & F_RANDOM), bool(flags & F_PER_SYLLABLE)))
        pauses = [self.pauses[0] + [(self.current[0], None)], self.pauses[1] + [(self.current[1], None)]]
        for t in range(2):
            nlookups = len(tables[t].LookupList.Lookup) if tables[t] is not None else 0
            lookups = m.lookups[t]
            pi = last = 0
            for stage in range(pauses[t][-1][0] + 1):
                if req[t][0] is not None and req_stage[t] == stage:
                    for li in tables[t].FeatureList.FeatureRecord[req[t][0]].Feature.LookupListIndex:
                        if li < nlookups:
                            lookups.append(Lookup(li, GLOBAL_MASK))
                for tag, index, stages, mask, az, aj, rnd, ps in feats:
                    if stages[t] == stage and index[t] is not None:
                        for li in tables[t].FeatureList.FeatureRecord[index[t]].Feature.LookupListIndex:
                            if li < nlookups:
                                lookups.append(Lookup(li, mask, az, aj, rnd, ps))
                part = sorted(lookups[last:], key=lambda lk: lk.index)
                del lookups[last:]
                for lk in part:
                    if len(lookups) > last and lookups[-1].index == lk.index:
                        lookups[-1].mask |= lk.mask
                        lookups[-1].auto_zwnj &= lk.auto_zwnj
                        lookups[-1].auto_zwj &= lk.auto_zwj
                    else:
                        lookups.append(lk)
                last = len(lookups)
                if pi < len(pauses[t]) and pauses[t][pi][0] == stage:
                    m.stages[t].append((last, pauses[t][pi][1]))
                    pi += 1
        return m


# ---------------------------------------------------------------- would-substitute (Indic plans)
def _subtable_cover(t, st):
    if t in (1, 2):
        return set(st.mapping)
    if t == 3:
        return set(st.alternates)
    if t == 4:
        return set(st.ligatures)
    if t in (5, 6):
        if st.Format == 3:
            covs = st.Coverage if t == 5 else st.InputCoverage
            return set(covs[0].glyphs) if covs else set()
        return set(st.Coverage.glyphs)
    if t == 8:
        return set(st.Coverage.glyphs)
    return set()


def would_apply(font, li, names, zero_context):
    """Would GSUB lookup li apply to exactly these glyphs (names), lookup flags and context
    ignored (HarfBuzz's hb_ot_layout_lookup_would_substitute)."""
    lk = font.gsub.LookupList.Lookup[li]
    subs = list(subtables(lk))
    if not names or not any(names[0] in _subtable_cover(t, st) for t, st in subs):
        return False
    n = len(names)
    for t, st in subs:
        if t in (1, 2):
            if n == 1 and names[0] in st.mapping:
                return True
        elif t == 3:
            if n == 1 and names[0] in st.alternates:
                return True
        elif t == 4:
            for lig in st.ligatures.get(names[0], []):
                if len(lig.Component) + 1 == n and list(lig.Component) == names[1:]:
                    return True
        elif t == 8:
            if n == 1 and names[0] in st.Coverage.glyphs:
                return True
        elif t in (5, 6):
            chain = t == 6
            if st.Format == 1:
                ci = coverage_index(st.Coverage, names[0])
                sets = st.ChainSubRuleSet if chain else st.SubRuleSet
                if ci is None or ci >= len(sets) or sets[ci] is None:
                    continue
                rules = sets[ci].ChainSubRule if chain else sets[ci].SubRule
                for r in rules:
                    if chain and zero_context and (r.Backtrack or r.LookAhead):
                        continue
                    if len(r.Input) + 1 == n and list(r.Input) == names[1:]:
                        return True
            elif st.Format == 2:
                cd = st.InputClassDef if chain else st.ClassDef
                k = class_of(cd, names[0])
                sets = st.ChainSubClassSet if chain else st.SubClassSet
                if k >= len(sets) or sets[k] is None:
                    continue
                rules = sets[k].ChainSubClassRule if chain else sets[k].SubClassRule
                for r in rules:
                    if chain and zero_context and (r.Backtrack or r.LookAhead):
                        continue
                    if len(r.Input if chain else r.Class) + 1 == n and \
                            all(class_of(cd, names[i + 1]) == v for i, v in enumerate(r.Input if chain else r.Class)):
                        return True
            else:
                covs = st.InputCoverage if chain else st.Coverage
                if chain and zero_context and (st.BacktrackCoverage or st.LookAheadCoverage):
                    continue
                if len(covs) == n and all(names[i] in covs[i].glyphs for i in range(1, n)):
                    return True
    return False


# ---------------------------------------------------------------- apply context
class Ctx:
    def __init__(self, font, buf, table, gpos):
        self.font, self.buf, self.table, self.gpos = font, buf, table, gpos
        self.lookups = table.LookupList.Lookup
        self.lookup_props = 0
        self.auto_zwnj = self.auto_zwj = True
        self.lookup_mask = 1
        self.nesting = MAX_NESTING
        self.last_base, self.last_base_until = -1, 0
        self.per_syllable = False

    # glyph properties against the lookup flags
    def check_glyph_property(self, info, match_props):
        props = info.props
        if props & match_props & IGNORE_FLAGS:
            return False
        if props & MARK:
            if match_props & USE_MARK_FILTERING_SET:
                return self.font.mark_set_covers(match_props >> 16, info.glyph)
            if match_props & MARK_ATTACHMENT_TYPE:
                return (match_props & MARK_ATTACHMENT_TYPE) == (props & MARK_ATTACHMENT_TYPE)
        return True

    def set_glyph_class(self, info, glyph, class_guess=0, ligature=False, component=False):
        props = info.props | SUBSTITUTED
        if ligature:
            props |= LIGATED
            props &= ~MULTIPLIED
        if component:
            props |= MULTIPLIED
        if self.font.classdef is not None:
            props &= PRESERVE
            info.props = props | self.font.glyph_props(glyph)
        elif class_guess:
            props &= PRESERVE
            info.props = props | class_guess
        else:
            info.props = props

    def replace_glyph(self, g):
        self.set_glyph_class(self.buf.cur(), g)
        self.buf.replace_glyph(g)

    def replace_glyph_inplace(self, g):
        self.set_glyph_class(self.buf.cur(), g)
        self.buf.cur().glyph = g

    def replace_glyph_with_ligature(self, g, klass):
        self.set_glyph_class(self.buf.cur(), g, klass, ligature=True)
        self.buf.replace_glyph(g)

    def output_glyph_for_component(self, g, klass):
        self.set_glyph_class(self.buf.cur(), g, klass, component=True)
        self.buf.output_glyph(g)


class Skippy:
    """HarfBuzz's skipping iterator."""

    def __init__(self, c, context_match):
        self.c = c
        gp = c.gpos
        self.ignore_zwnj = gp or (context_match and c.auto_zwnj)
        self.ignore_zwj = context_match or c.auto_zwj
        self.ignore_hidden = gp
        self.mask = -1 if context_match else c.lookup_mask
        self.lookup_props = c.lookup_props
        self.per_syllable = (not gp) and c.per_syllable
        self.syllable = 0
        self.match = None

    def reset(self, start, num_items, buf_len):
        self.idx = start
        self.num_items = num_items
        self.end = buf_len
        b = self.c.buf
        self.syllable = b.cur().syllable if start == b.idx else 0

    def may_skip(self, info):
        if not self.c.check_glyph_property(info, self.lookup_props):
            return 'yes'
        if info.ign and not info.substituted() and (self.ignore_hidden or not info.hidden) and \
                (self.ignore_zwnj or not info.zwnj) and (self.ignore_zwj or not info.zwj):
            return 'maybe'
        return 'no'

    def may_match(self, info, k):
        if not (info.mask & self.mask) or (self.per_syllable and self.syllable and self.syllable != info.syllable):
            return 'no'
        if self.match:
            return 'yes' if self.match(info, k) else 'no'
        return 'maybe'

    def check(self, info, k):
        skip = self.may_skip(info)
        if skip == 'yes':
            return 'skip'
        m = self.may_match(info, k)
        if m == 'yes' or (m == 'maybe' and skip == 'no'):
            return 'match'
        if skip == 'no':
            return 'nomatch'
        return 'skip'

    def next(self, k=0):
        info = self.c.buf.info
        stop = self.end - self.num_items
        while self.idx < stop:
            self.idx += 1
            r = self.check(info[self.idx], k)
            if r == 'match':
                self.num_items -= 1
                return True
            if r == 'nomatch':
                return False
        return False

    def prev(self, arr, k=0):
        stop = self.num_items - 1
        while self.idx > stop:
            self.idx -= 1
            r = self.check(arr[self.idx], k)
            if r == 'match':
                self.num_items -= 1
                return True
            if r == 'nomatch':
                return False
        return False


def coverage_index(cov, glyph_name):
    try:
        return cov.glyphs.index(glyph_name)
    except ValueError:
        return None


def class_of(cd, name):
    return cd.classDefs.get(name, 0) if cd is not None else 0


# ---------------------------------------------------------------- matching
def match_input(c, count, matchers, match_positions):
    """matchers: list of callables (info) -> bool for components 1..count-1."""
    b = c.buf
    sk = Skippy(c, False)
    sk.reset(b.idx, count - 1, len(b.info))
    sk.match = lambda info, k: matchers[k](info)
    total = 0
    first_lig_id = b.cur().lig_id()
    first_lig_comp = b.cur().lig_comp()
    ligbase = 0                                         # 0 not checked, 1 may not skip, 2 may skip
    for i in range(1, count):
        if not sk.next(i - 1):
            return None
        match_positions[i] = sk.idx
        inf = b.info[sk.idx]
        this_id, this_comp = inf.lig_id(), inf.lig_comp()
        if first_lig_id and first_lig_comp:
            if first_lig_id != this_id or first_lig_comp != this_comp:
                if ligbase == 0:
                    found = False
                    out = b.out
                    j = len(out)
                    while j and out[j - 1].lig_id() == first_lig_id:
                        if out[j - 1].lig_comp() == 0:
                            j -= 1
                            found = True
                            break
                        j -= 1
                    ligbase = 2 if found and sk.may_skip(out[j]) == 'yes' else 1
                if ligbase == 1:
                    return None
        else:
            if this_id and this_comp and this_id != first_lig_id:
                return None
        total += inf.lig_num_comps()
    end = sk.idx + 1
    total += b.cur().lig_num_comps()
    match_positions[0] = b.idx
    return end, total


def match_backtrack(c, matchers):
    b = c.buf
    sk = Skippy(c, True)
    arr = b.out if b.have_output else b.info
    sk.reset(b.backtrack_len(), len(matchers), len(b.info))
    sk.idx = b.backtrack_len()
    sk.match = lambda info, k: matchers[k](info)
    for i in range(len(matchers)):
        if not sk.prev(arr, i):
            return False
    return True


def match_lookahead(c, matchers, start):
    b = c.buf
    sk = Skippy(c, True)
    sk.reset(start - 1, len(matchers), len(b.info))
    sk.match = lambda info, k: matchers[k](info)
    for i in range(len(matchers)):
        if not sk.next(i):
            return False
    return True


def ligate_input(c, count, match_positions, match_end, lig_glyph, total):
    b = c.buf
    b.merge_clusters(b.idx, match_end)
    is_base_lig = b.info[match_positions[0]].is_base()
    is_mark_lig = b.info[match_positions[0]].is_mark()
    for i in range(1, count):
        if not b.info[match_positions[i]].is_mark():
            is_base_lig = is_mark_lig = False
            break
    is_lig = not is_base_lig and not is_mark_lig
    klass = LIGATURE if is_lig else 0
    lig_id = b.next_serial() if is_lig else 0
    last_lig_id = b.cur().lig_id()
    last_num = b.cur().lig_num_comps()
    so_far = last_num
    if is_lig:
        b.cur().lig = ((lig_id << 5) & 0xE0) | IS_LIG_BASE | (total & 0x0F)
        if b.cur().gc == 'Mn':
            b.cur().gc = 'Lo'
    c.replace_glyph_with_ligature(lig_glyph, klass)
    for i in range(1, count):
        while b.idx < match_positions[i]:
            if is_lig:
                this_comp = b.cur().lig_comp()
                if this_comp == 0:
                    this_comp = last_num
                new_comp = so_far - last_num + min(this_comp, last_num)
                b.cur().lig = ((lig_id << 5) & 0xE0) | (new_comp & 0x0F)
            b.next_glyph()
        last_lig_id = b.cur().lig_id()
        last_num = b.cur().lig_num_comps()
        so_far += last_num
        b.idx += 1                                      # the component itself goes
    if not is_mark_lig and last_lig_id:
        for i in range(b.idx, len(b.info)):
            if last_lig_id != b.info[i].lig_id():
                break
            this_comp = b.info[i].lig_comp()
            if not this_comp:
                break
            new_comp = so_far - last_num + min(this_comp, last_num)
            b.info[i].lig = ((lig_id << 5) & 0xE0) | (new_comp & 0x0F)


def apply_lookup_records(c, count, match_positions, records, match_end):
    b = c.buf
    bl = b.backtrack_len()
    end = bl + match_end - b.idx
    delta = bl - b.idx
    mp = [p + delta for p in match_positions[:count]]
    for rec in records:
        idx = rec.SequenceIndex
        if idx >= count:
            continue
        orig_len = b.backtrack_len() + b.lookahead_len()
        if mp[idx] >= orig_len:
            continue
        b.move_to(mp[idx])
        if not recurse(c, rec.LookupListIndex):
            continue
        new_len = b.backtrack_len() + b.lookahead_len()
        delta = new_len - orig_len
        if not delta:
            continue
        end += delta
        if end < mp[idx]:
            delta += mp[idx] - end
            end = mp[idx]
        nxt = idx + 1
        if delta > 0:
            if delta + count > MAX_CONTEXT:
                break
        else:
            delta = max(delta, nxt - count)
            nxt -= delta
        mp[nxt + delta:count + delta] = mp[nxt:count]
        if len(mp) < count + delta:
            mp += [0] * (count + delta - len(mp))
        del mp[count + delta:]
        nxt += delta
        count += delta
        for j in range(idx + 1, nxt):
            mp[j] = mp[j - 1] + 1
        while nxt < count:
            mp[nxt] += delta
            nxt += 1
    b.move_to(end)


def recurse(c, li):
    if c.nesting <= 0:
        return False
    c.nesting -= 1
    lk = c.lookups[li]
    saved = c.lookup_props
    c.lookup_props = lookup_props(lk, c.font)
    ret = apply_subtables(c, lk)
    c.lookup_props = saved
    c.nesting += 1
    return ret


def lookup_props(lk, font):
    p = lk.LookupFlag
    if p & USE_MARK_FILTERING_SET:
        p |= lk.MarkFilteringSet << 16
        if lk.MarkFilteringSet >= len(font.marksets):
            p &= ~USE_MARK_FILTERING_SET                # no such set: the flag is dropped
    return p


def subtables(lk):
    t = lk.LookupType
    for st in lk.SubTable:
        if (t == 7 and lk.SubTable and hasattr(st, 'ExtSubTable')) or (t == 9 and hasattr(st, 'ExtSubTable')):
            yield st.ExtensionLookupType, st.ExtSubTable
        else:
            yield t, st


def apply_subtables(c, lk):
    for t, st in subtables(lk):
        if (apply_gpos if c.gpos else apply_gsub)(c, t, st):
            return True
    return False


def glyph_name(c, info):
    return c.font.order[info.glyph]


# ---------------------------------------------------------------- context lookups (both tables)
def apply_context(c, st, t):
    b = c.buf
    name = glyph_name(c, b.cur())
    chain = t in (6, 8)
    fmt = st.Format
    if fmt == 1:
        cov = st.Coverage
        ci = coverage_index(cov, name)
        if ci is None:
            return False
        sets = st.ChainSubRuleSet if hasattr(st, 'ChainSubRuleSet') else \
            st.ChainPosRuleSet if hasattr(st, 'ChainPosRuleSet') else \
            st.SubRuleSet if hasattr(st, 'SubRuleSet') else st.PosRuleSet
        rs = sets[ci]
        if rs is None:
            return False
        rules = getattr(rs, 'ChainSubRule', None) or getattr(rs, 'ChainPosRule', None) or \
            getattr(rs, 'SubRule', None) or getattr(rs, 'PosRule', None) or []
        for r in rules:
            if chain:
                back, inp, look = r.Backtrack, r.Input, r.LookAhead
            else:
                back, inp, look = [], r.Input, []
            recs = getattr(r, 'SubstLookupRecord', None) or getattr(r, 'PosLookupRecord', None) or []
            if context_apply(c, [glyph_eq(g) for g in back], [glyph_eq(g) for g in inp],
                             [glyph_eq(g) for g in look], recs):
                return True
        return False
    if fmt == 2:
        cov = st.Coverage
        if coverage_index(cov, name) is None:
            return False
        if chain:
            bcd, icd, lcd = st.BacktrackClassDef, st.InputClassDef, st.LookAheadClassDef
        else:
            bcd = lcd = None
            icd = st.ClassDef
        k = class_of(icd, name)
        sets = getattr(st, 'ChainSubClassSet', None) or getattr(st, 'ChainPosClassSet', None) or \
            getattr(st, 'SubClassSet', None) or getattr(st, 'PosClassSet', None) or []
        if k >= len(sets) or sets[k] is None:
            return False
        rs = sets[k]
        rules = getattr(rs, 'ChainSubClassRule', None) or getattr(rs, 'ChainPosClassRule', None) or \
            getattr(rs, 'SubClassRule', None) or getattr(rs, 'PosClassRule', None) or []
        for r in rules:
            if chain:
                back, inp, look = r.Backtrack, r.Input, r.LookAhead
            else:
                back, inp, look = [], r.Class, []
            recs = getattr(r, 'SubstLookupRecord', None) or getattr(r, 'PosLookupRecord', None) or []
            if context_apply(c, [class_eq(c, bcd, v) for v in back], [class_eq(c, icd, v) for v in inp],
                             [class_eq(c, lcd, v) for v in look], recs):
                return True
        return False
    # format 3: coverages
    if chain:
        back, inp, look = st.BacktrackCoverage, st.InputCoverage, st.LookAheadCoverage
    else:
        back, inp, look = [], st.Coverage, []
    if coverage_index(inp[0], name) is None:
        return False
    recs = getattr(st, 'SubstLookupRecord', None) or getattr(st, 'PosLookupRecord', None) or []
    return context_apply(c, [cov_has(c, x) for x in back], [cov_has(c, x) for x in inp[1:]],
                         [cov_has(c, x) for x in look], recs)


def glyph_eq(gname):
    return lambda info, _n=gname: info._name == _n


def class_eq(c, cd, v):
    return lambda info, _cd=cd, _v=v: class_of(_cd, c.font.order[info.glyph]) == _v


def cov_has(c, cov):
    s = set(cov.glyphs)
    return lambda info, _s=s: c.font.order[info.glyph] in _s


def context_apply(c, back, inp, look, recs):
    b = c.buf
    for arr in (b.info, b.out):
        for i in arr:
            i._name = c.font.order[i.glyph]
    count = len(inp) + 1
    mp = [0] * max(count, MAX_CONTEXT)
    m = match_input(c, count, inp, mp)
    if m is None:
        return False
    end, _ = m
    if not match_backtrack(c, back):
        return False
    if not match_lookahead(c, look, end):
        return False
    apply_lookup_records(c, count, mp, recs, end)
    return True


# ---------------------------------------------------------------- GSUB
def apply_gsub(c, t, st):
    b = c.buf
    name = glyph_name(c, b.cur())
    if t == 1:
        g = st.mapping.get(name)
        if g is None:
            return False
        c.replace_glyph(c.font.gid[g])
        return True
    if t == 2:
        seq = st.mapping.get(name)
        if seq is None:
            return False
        if len(seq) == 1:
            c.replace_glyph(c.font.gid[seq[0]])
            return True
        if len(seq) == 0:
            b.delete_glyph()
            return True
        klass = BASE if b.cur().is_ligature() else 0
        lig_id = b.cur().lig_id()
        for i, gname in enumerate(seq):
            if not lig_id:
                b.cur().lig = i & 0x0F
            c.output_glyph_for_component(c.font.gid[gname], klass)
        b.skip_glyph()
        return True
    if t == 3:
        alts = st.alternates.get(name)
        if not alts:
            return False
        c.replace_glyph(c.font.gid[alts[0]])
        return True
    if t == 4:
        ligs = st.ligatures.get(name)
        if not ligs:
            return False
        for lig in ligs:
            count = len(lig.Component) + 1
            if count == 1:
                c.replace_glyph(c.font.gid[lig.LigGlyph])
                return True
            comps = [c.font.gid[x] for x in lig.Component]
            mp = [0] * count
            m = match_input(c, count, [(lambda info, _g=g: info.glyph == _g) for g in comps], mp)
            if m is None:
                continue
            end, total = m
            ligate_input(c, count, mp, end, c.font.gid[lig.LigGlyph], total)
            return True
        return False
    if t in (5, 6):
        return apply_context(c, st, t)
    if t == 8:
        cov = st.Coverage
        ci = coverage_index(cov, name)
        if ci is None:
            return False
        for arr in (b.info, b.out):
            for i in arr:
                i._name = c.font.order[i.glyph]
        back = [cov_has(c, x) for x in st.BacktrackCoverage]
        look = [cov_has(c, x) for x in st.LookAheadCoverage]
        if match_backtrack(c, back) and match_lookahead(c, look, b.idx + 1):
            c.replace_glyph_inplace(c.font.gid[st.Substitute[ci]])
            return True
        return False
    return False


# ---------------------------------------------------------------- GPOS
def value(c, fmt_rec, pos):
    if fmt_rec is None:
        return False
    for attr, field in (('XPlacement', 'xo'), ('YPlacement', 'yo'), ('XAdvance', 'xa')):
        v = getattr(fmt_rec, attr, None)
        if v:
            setattr(pos, field, getattr(pos, field) + v)
    return True


def anchor_xy(a):
    return a.XCoordinate, a.YCoordinate


def find_base(c, accept_multiplied):
    b = c.buf
    sk = Skippy(c, False)
    sk.lookup_props = 8                                   # IgnoreMarks
    if c.last_base_until > b.idx:
        c.last_base_until, c.last_base = 0, -1
    j = b.idx
    while j > c.last_base_until:
        info = b.info[j - 1]
        r = sk.check(info, 0)
        if r == 'match' and accept_multiplied and not accept(b, j - 1) and accept_multiplied(info) is None:
            r = 'skip'
        if r == 'match':
            c.last_base = j - 1
            break
        j -= 1
    c.last_base_until = b.idx
    return c.last_base


def accept(b, idx):
    info = b.info
    return (not info[idx].multiplied() or info[idx].lig_comp() == 0 or idx == 0 or info[idx - 1].is_mark() or
            not info[idx - 1].multiplied() or info[idx].lig_id() != info[idx - 1].lig_id() or
            info[idx].lig_comp() != info[idx - 1].lig_comp() + 1)


def mark_apply(c, mark_rec, base_anchor, glyph_pos):
    if base_anchor is None:
        return False
    b = c.buf
    mx, my = anchor_xy(mark_rec.MarkAnchor)
    bx, by = anchor_xy(base_anchor)
    o = b.pos[b.idx]
    o.xo = bx - mx
    o.yo = by - my
    o.type = ATTACH_MARK
    o.chain = glyph_pos - b.idx
    c.has_attachment = True
    b.idx += 1
    return True


def apply_gpos(c, t, st):
    b = c.buf
    name = glyph_name(c, b.cur())
    if t == 1:
        ci = coverage_index(st.Coverage, name)
        if ci is None:
            return False
        v = st.Value if st.Format == 1 else st.Value[ci]
        value(c, v, b.pos[b.idx])
        b.idx += 1
        return True
    if t == 2:
        ci = coverage_index(st.Coverage, name)
        if ci is None:
            return False
        sk = Skippy(c, False)
        sk.reset(b.idx, 1, len(b.info))
        if not sk.next():
            return False
        second = b.info[sk.idx]
        sname = c.font.order[second.glyph]
        if st.Format == 1:
            ps = st.PairSet[ci]
            for rec in ps.PairValueRecord:
                if rec.SecondGlyph == sname:
                    value(c, rec.Value1, b.pos[b.idx])
                    value(c, rec.Value2, b.pos[sk.idx])
                    pos = sk.idx
                    if st.ValueFormat2:
                        pos += 1
                    b.idx = pos
                    return True
            return False
        k1 = class_of(st.ClassDef1, name)
        k2 = class_of(st.ClassDef2, sname)
        if k1 >= st.Class1Count or k2 >= st.Class2Count:
            return False
        rec = st.Class1Record[k1].Class2Record[k2]
        if st.ValueFormat1:
            value(c, rec.Value1, b.pos[b.idx])
        if st.ValueFormat2:
            value(c, rec.Value2, b.pos[sk.idx])
        pos = sk.idx
        if st.ValueFormat2:
            pos += 1
        b.idx = pos
        return True
    if t == 3:
        return False                                      # cursive: not in the shipped fonts yet
    if t in (4, 5):
        mi = coverage_index(st.MarkCoverage, name)
        if mi is None:
            return False
        if t == 4:
            base_cov = st.BaseCoverage
            j = find_base(c, lambda info: coverage_index(base_cov, c.font.order[info.glyph]))
        else:
            j = find_base(c, None)
        if j == -1:
            return False
        bname = c.font.order[b.info[j].glyph]
        mrec = st.MarkArray.MarkRecord[mi]
        if t == 4:
            bi = coverage_index(st.BaseCoverage, bname)
            if bi is None:
                return False
            anchor = st.BaseArray.BaseRecord[bi].BaseAnchor[mrec.Class]
            return mark_apply(c, mrec, anchor, j)
        li = coverage_index(st.LigatureCoverage, bname)
        if li is None:
            return False
        la = st.LigatureArray.LigatureAttach[li]
        comp_count = la.ComponentCount
        if not comp_count:
            return False
        lig_id, mark_id = b.info[j].lig_id(), b.cur().lig_id()
        mark_comp = b.cur().lig_comp()
        if lig_id and lig_id == mark_id and mark_comp > 0:
            comp = min(comp_count, mark_comp) - 1
        else:
            comp = comp_count - 1
        anchor = la.ComponentRecord[comp].LigatureAnchor[mrec.Class]
        return mark_apply(c, mrec, anchor, j)
    if t == 6:
        m1 = coverage_index(st.Mark1Coverage, name)
        if m1 is None:
            return False
        sk = Skippy(c, False)
        sk.lookup_props = c.lookup_props & ~IGNORE_FLAGS
        sk.reset(b.idx, 1, len(b.info))
        if not sk.prev(b.info):
            return False
        j = sk.idx
        if not b.info[j].is_mark():
            return False
        id1, id2 = b.cur().lig_id(), b.info[j].lig_id()
        comp1, comp2 = b.cur().lig_comp(), b.info[j].lig_comp()
        good = False
        if id1 == id2:
            good = id1 == 0 or comp1 == comp2
        else:
            good = (id1 > 0 and not comp1) or (id2 > 0 and not comp2)
        if not good:
            return False
        m2 = coverage_index(st.Mark2Coverage, c.font.order[b.info[j].glyph])
        if m2 is None:
            return False
        mrec = st.Mark1Array.MarkRecord[m1]
        anchor = st.Mark2Array.Mark2Record[m2].Mark2Anchor[mrec.Class]
        return mark_apply(c, mrec, anchor, j)
    if t in (7, 8):
        return apply_context(c, st, t)
    return False


# ---------------------------------------------------------------- running a table
def run_table(c, m, gpos):
    """The table's lookups stage by stage, each stage's pause after it."""
    b = c.buf
    t = 1 if gpos else 0
    i = 0
    for last, pause in m.stages[t]:
        for entry in m.lookups[t][i:last]:
            lk = c.lookups[entry.index]
            c.lookup_props = lookup_props(lk, c.font)
            c.auto_zwnj, c.auto_zwj = entry.auto_zwnj, entry.auto_zwj
            c.lookup_mask = entry.mask
            c.per_syllable = entry.per_syllable
            c.last_base, c.last_base_until = -1, 0
            if not b.info or not c.lookup_mask:
                continue
            if lk.LookupType == 8 and not gpos:
                b.idx = len(b.info) - 1
                while b.idx >= 0:
                    cur = b.cur()
                    if (cur.mask & c.lookup_mask) and c.check_glyph_property(cur, c.lookup_props):
                        apply_subtables(c, lk)
                    b.idx -= 1
                b.idx = 0
                continue
            if not gpos:
                b.clear_output()
            b.idx = 0
            while b.idx < len(b.info):
                cur = b.cur()
                applied = False
                if (cur.mask & c.lookup_mask) and c.check_glyph_property(cur, c.lookup_props):
                    applied = apply_subtables(c, lk)
                if not applied:
                    if gpos:
                        b.idx += 1
                    else:
                        b.next_glyph()
            if not gpos:
                b.sync()
        i = last
        if pause:
            b.idx = 0
            pause(b)


# ---------------------------------------------------------------- normalization
def normalize(b, font, shaper=None):
    """HarfBuzz's composed-diacritics normalization against the font (an Indic shaper: no
    short circuit, its own decompose / compose exceptions)."""
    short = shaper is None or not shaper.no_short_circuit
    decompose2_ = shaper.decompose if shaper else decompose2
    compose_ = shaper.compose if shaper else compose
    # decompose
    b.clear_output()
    count = len(b.info)
    all_simple = True

    def next_char(g):
        b.cur().glyph = g
        b.next_glyph()

    def output_char(u, g):
        n = b.cur().copy()
        n.cp = u
        n.glyph = g
        n.set_unicode(u)
        b.output_info(n)

    def decompose(shortest, ab):
        d = decompose2_(ab)
        if d is None:
            return 0
        a, bb = d
        b_glyph = 0
        if bb:
            b_glyph = font.nominal(bb)
            if b_glyph is None:
                return 0
        a_glyph = font.nominal(a)
        has_a = a_glyph is not None
        if shortest and has_a:
            output_char(a, a_glyph)
            if bb:
                output_char(bb, b_glyph)
                return 2
            return 1
        ret = decompose(shortest, a)
        if ret:
            if bb:
                output_char(bb, b_glyph)
                return ret + 1
            return ret
        if has_a:
            output_char(a, a_glyph)
            if bb:
                output_char(bb, b_glyph)
                return 2
            return 1
        return 0

    def decompose_current(shortest):
        u = b.cur().cp
        g = font.nominal(u)
        if shortest and g is not None:
            next_char(g)
            return
        if decompose(shortest, u):
            b.skip_glyph()
            return
        if not shortest and g is not None:
            next_char(g)
            return
        if b.cur().gc == 'Zs':
            st = SPACE_TYPES.get(u, 0)
            space = font.nominal(0x20)
            if st and space is not None:
                b.cur().space = st
                next_char(space)                          # widened in fallback_spaces
                return
        if u == 0x2011:
            other = font.nominal(0x2010)
            if other is not None:
                next_char(other)
                return
        next_char(0)

    while b.idx < count:
        end = b.idx + 1
        while end < count and not is_mark_gc(b.info[end].gc):
            end += 1
        if end < count:
            end -= 1
        while b.idx < end:
            decompose_current(short)
        if b.idx == count:
            break
        all_simple = False
        end = b.idx + 1
        while end < count and is_mark_gc(b.info[end].gc):
            end += 1
        if any(is_variation_selector(b.info[i].cp) for i in range(b.idx, end)):
            # a variation selector: no normalization, each its own glyph
            while b.idx < end - 1:
                if is_variation_selector(b.info[b.idx + 1].cp):
                    vg = font.variation(b.cur().cp, b.info[b.idx + 1].cp)
                    if vg is not None:
                        b.cur().glyph = vg
                        b.next_glyph()
                        b.skip_glyph()
                    else:
                        g = font.nominal(b.cur().cp)
                        next_char(0 if g is None else g)
                    while b.idx < end and is_variation_selector(b.cur().cp):
                        g = font.nominal(b.cur().cp)
                        next_char(0 if g is None else g)
                else:
                    g = font.nominal(b.cur().cp)
                    next_char(0 if g is None else g)
            if b.idx < end:
                g = font.nominal(b.cur().cp)
                next_char(0 if g is None else g)
        else:
            while b.idx < end:
                decompose_current(False)
    b.sync()
    if all_simple:
        return
    # reorder marks by combining class
    i = 0
    count = len(b.info)
    while i < count:
        if b.info[i].mcc == 0:
            i += 1
            continue
        end = i + 1
        while end < count and b.info[end].mcc != 0:
            end += 1
        if end - i <= 32:
            b.sort(i, end, lambda inf: inf.mcc)
        i = end
    # recompose
    b.clear_output()
    count = len(b.info)
    starter = 0
    b.next_glyph()
    while b.idx < count:
        cur = b.cur()
        if is_mark_gc(cur.gc):
            prev = b.out[-1]
            if starter == len(b.out) - 1 or prev.mcc < cur.mcc:
                comp = compose_(b.out[starter].cp, cur.cp)
                if comp is not None:
                    g = font.nominal(comp)
                    if g is not None:
                        b.next_glyph()
                        b.merge_out_clusters(starter, len(b.out))
                        b.out.pop()
                        st = b.out[starter]
                        st.cp = comp
                        st.glyph = g
                        st.set_unicode(comp)
                        continue
            if starter < len(b.out) - 1 and prev.mcc > cur.mcc:
                starter = len(b.out)
        b.next_glyph()
        if b.out[-1].mcc == 0:
            starter = len(b.out) - 1
    b.sync()


# ---------------------------------------------------------------- the shaper
def pick_shaper(script, gsub_script):
    """HarfBuzz's shaper choice: Devanagari through the Indic shaper unless the font's GSUB only
    has DFLT / latn for it; everything else the default shaper (None)."""
    if script == 'Deva':
        tag = gsub_script.ScriptTag if gsub_script is not None else None
        if tag in ('DFLT', 'latn'):
            return None
        if tag is not None and tag[3] == '3':
            raise NotImplementedError('the Universal Shaping Engine (deva / dev3 fonts)')
        from indic import IndicShaper
        return IndicShaper(script)
    return None


def shape(font, cps, script=None, language=None, shaper=None):
    if script is None:
        script = guess_script(cps)
    infos = [Info(cp, i) for i, cp in enumerate(cps)]
    b = Buffer(infos)
    # ZWJ (and an Extended_Pictographic after it) continues a grapheme
    i = 0
    while i < len(infos):
        if infos[i].zwj:
            infos[i].cont = True
        i += 1
    # grapheme clusters
    if any(cp >= 0x80 for cp in cps):
        start = 0
        for i in range(1, len(infos) + 1):
            if i == len(infos) or not infos[i].cont:
                b.merge_clusters(start, i)
                start = i
    tags = script_tags(script)
    gsub_s = select_script(font.gsub, tags)
    gpos_s = select_script(font.gpos, tags)
    gsub_ls, gpos_ls = langsys(gsub_s, language), langsys(gpos_s, language)
    if shaper is None:
        shaper = pick_shaper(script, gsub_s)
    # the plan
    mb = MapBuilder()
    mb.enable_feature('rvrn')
    mb.add_gsub_pause(None)
    mb.enable_feature('ltra')
    mb.enable_feature('ltrm')
    for tag in ('frac', 'numr', 'dnom'):
        mb.add_feature(tag)
    mb.enable_feature('rand', F_RANDOM, MAX_VALUE)
    mb.enable_feature('Harf')
    mb.enable_feature('HARF')
    if shaper:
        shaper.collect_features(mb)
    mb.enable_feature('Buzz')
    mb.enable_feature('BUZZ')
    for tag, flags in COMMON + HORIZONTAL:
        mb.add_feature(tag, flags)
    if shaper:
        shaper.override_features(mb)
    m = mb.compile((font.gsub, font.gpos), (gsub_s, gpos_s), (gsub_ls, gpos_ls))
    if shaper:
        shaper.data_create(m, font)
        shaper.preprocess_text(b, font)
    # normalization
    normalize(b, font, shaper)
    # masks, glyphs
    for inf in b.info:
        inf.mask = m.global_mask
    if shaper:
        shaper.setup_masks(b, font)
    has_gpos_kern = gpos_ls is not None and any(
        font.gpos.FeatureList.FeatureRecord[i].FeatureTag == 'kern' for i in gpos_ls.FeatureIndex)
    apply_gpos = font.gpos is not None
    apply_kern = bool(font.kern) and not (has_gpos_kern and apply_gpos)
    # GSUB
    for inf in b.info:
        inf.props = font.glyph_props(inf.glyph)
        inf.lig = 0
        if font.classdef is None:
            # no glyph classes in the font: nonspacing marks are marks, the rest bases
            inf.props = MARK if inf.gc == 'Mn' and not inf.ign else BASE
    if font.gsub:
        run_table(Ctx(font, b, font.gsub, False), m, False)
    elif shaper:
        # no GSUB: the shaper's pauses still run
        for _, pause in m.stages[0]:
            if pause:
                pause(b)
    # positions
    b.pos = [Pos() for _ in b.info]
    for inf, p in zip(b.info, b.pos):
        p.xa = font.advance(inf.glyph)
    fallback_spaces(b, font)
    attached = False
    if font.gpos:
        c = Ctx(font, b, font.gpos, True)
        c.has_attachment = False
        run_table(c, m, True)
        attached = c.has_attachment
    if apply_kern:
        kern_table(font, b, m.get_mask('kern'))
    zero_marks = shaper.zero_width_marks if shaper else 'late'
    if zero_marks == 'late':
        for inf, p in zip(b.info, b.pos):
            if inf.is_mark():
                p.xa = p.ya = 0
    for inf, p in zip(b.info, b.pos):
        if inf.is_default_ignorable():
            p.xa = p.ya = p.xo = p.yo = 0
    if attached:
        for i in range(len(b.pos)):
            propagate(b.pos, i, MAX_NESTING)
    # default ignorables hidden: the space glyph
    space = font.nominal(0x20)
    out = []
    for inf, p in zip(b.info, b.pos):
        g = inf.glyph
        if inf.is_default_ignorable():
            if space is None:
                continue
            g = space
        out.append((g, inf.cluster, p.xa, p.ya, p.xo, p.yo))
    return out


def kern_table(font, b, mask):
    """The legacy kern table (format 0), each subtable over the run: marks skipped, the value split
    between the pair (half on the first's advance, the rest on the second's advance and offset)."""
    c = Ctx(font, b, font.gpos or font.gsub or _Empty(), True)
    c.lookup_props = 8
    c.lookup_mask = mask
    for table in font.kern:
        idx = 0
        while idx < len(b.info):
            if not (b.info[idx].mask & mask):
                idx += 1
                continue
            b.idx = idx
            sk = Skippy(c, False)
            sk.reset(idx, 1, len(b.info))
            if not sk.next():
                idx += 1
                continue
            i, j = idx, sk.idx
            k = table.get((b.info[i].glyph, b.info[j].glyph), 0)
            if k:
                k1 = k >> 1
                k2 = k - k1
                b.pos[i].xa += k1
                b.pos[j].xa += k2
                b.pos[j].xo += k2
            idx = sk.idx


class _Empty:
    class LookupList:
        Lookup = []


def fallback_spaces(b, font):
    upem = font.tt['head'].unitsPerEm
    for inf, p in zip(b.info, b.pos):
        if inf.gc != 'Zs' or (inf.props & LIGATED):
            continue
        st = inf.space
        if st in (SPACE_EM, SPACE_EM_2, SPACE_EM_3, SPACE_EM_4, SPACE_EM_5, SPACE_EM_6, SPACE_EM_16):
            p.xa = (upem + st // 2) // st
        elif st == SPACE_4_EM_18:
            p.xa = upem * 4 // 18
        elif st == SPACE_FIGURE:
            for d in range(0x30, 0x3A):
                g = font.nominal(d)
                if g is not None:
                    p.xa = font.advance(g)
                    break
        elif st == SPACE_PUNCTUATION:
            g = font.nominal(0x2E)
            if g is None:
                g = font.nominal(0x2C)
            if g is not None:
                p.xa = font.advance(g)
        elif st == SPACE_NARROW:
            p.xa = int(p.xa / 2)


def propagate(pos, i, nesting):
    chain, typ = pos[i].chain, pos[i].type
    if not chain:
        return
    pos[i].chain = 0
    j = i + chain
    if j >= len(pos) or j < 0 or not nesting:
        return
    propagate(pos, j, nesting - 1)
    if typ & ATTACH_MARK:
        pos[i].xo += pos[j].xo
        pos[i].yo += pos[j].yo
        for k in range(j, i):
            pos[i].xo -= pos[k].xa
            pos[i].yo -= pos[k].ya

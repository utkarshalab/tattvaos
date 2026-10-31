"""What HarfBuzz's syllabic shapers share (hb-ot-shaper-syllabic.cc), for the Khmer, Myanmar and
Universal Shaping Engine models: syllables found by a grammar's automaton, dotted circles put
into broken clusters, the syllables cleared once their features are done.

Development-machine tooling only.
"""
import shapemodel as sm
import syllable as syl


def find_syllables(b, machine, cats, broken_type):
    """Each record's syllable (serial << 4 | type; serials 1 .. 15) from the categories cats ->
    whether a broken cluster was found."""
    serial, broken = 1, False
    for start, end, typ in syl.scan(machine, cats):
        for i in range(start, end):
            b.info[i].syllable = (serial << 4) | typ
        serial += 1
        if serial == 16:
            serial = 1
        broken |= typ == broken_type
    return broken


def syllables(b):
    """(start, end) of each run of one syllable value."""
    start, n = 0, len(b.info)
    while start < n:
        end = start + 1
        while end < n and b.info[end].syllable == b.info[start].syllable:
            end += 1
        yield start, end
        start = end


def insert_dotted_circles(b, font, broken_type, dc_cat, repha_cat=None, dc_pos=None):
    """A dotted circle at the start of every broken cluster (after its rephas), when the font has
    one: a record with only the glyph, the category (and position), the cluster, mask and
    syllable of the character it goes before."""
    g = font.nominal(0x25CC)
    if g is None:
        return False
    b.clear_output()
    b.idx = 0
    last = 0
    while b.idx < len(b.info):
        s = b.cur().syllable
        if last != s and (s & 0x0F) == broken_type:
            last = s
            cur = b.cur()
            dc = sm.Info.__new__(sm.Info)
            for f in sm.Info.__slots__:
                setattr(dc, f, 0)
            dc.cp, dc.glyph, dc.cluster, dc.mask, dc.syllable = 0x25CC, g, cur.cluster, cur.mask, s
            dc.gc = 'Cc'
            dc.ign = dc.zwj = dc.zwnj = dc.hidden = dc.cont = False
            dc._name = None
            dc.cat = dc_cat
            if dc_pos is not None:
                dc.pos = dc_pos
            if repha_cat is not None:
                while b.idx < len(b.info) and last == b.cur().syllable and b.cur().cat == repha_cat:
                    b.next_glyph()
            b.output_info(dc)
        else:
            b.next_glyph()
    b.sync()
    return True


def clear_syllables(b):
    """HarfBuzz's hb_syllabic_clear_var: features after this are not held to a syllable."""
    for inf in b.info:
        inf.syllable = 0

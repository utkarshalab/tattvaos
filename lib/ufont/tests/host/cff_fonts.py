"""Test fonts with CFF outlines, made from the shipped TrueType fonts (development machine only).

    make_cff(ttf path, out path, cid=False, subrs=False)

The glyf outlines become Type 2 charstrings (quadratic curves as exact cubics, fractions kept as
16.16 fixed numbers; the specializer's h / v / hh / vv / hv / vh / rcurveline / rlinecurve forms);
cid=True makes the font CID-keyed (ROS, an FDArray of two Font DICTs, FDSelect format 3 sending
odd glyphs to the second); subrs=True moves repeated charstring tails into local and global
subroutines (callsubr / callgsubr with their biases) and adds stem hints with hint masks.
"""
import random

from fontTools.ttLib import TTFont
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.fontBuilder import FontBuilder
from fontTools.misc.psCharStrings import T2CharString
from fontTools import cffLib


def make_cff(src, out, cid=False, subrs=False):
    tt = TTFont(src)
    order = tt.getGlyphOrder()
    gs = tt.getGlyphSet()
    hmtx = tt['hmtx']
    # CID-keyed fonts name glyphs by CID (the layout tables, naming the old ones, are left out)
    names = ['.notdef'] + ['cid%05d' % i for i in range(1, len(order))] if cid else order
    rename = dict(zip(order, names))
    charstrings = {}
    for name in order:
        pen = T2CharStringPen(hmtx[name][0], gs, roundTolerance=0)
        gs[name].draw(pen)
        charstrings[rename[name]] = pen.getCharString()
    fb = FontBuilder(tt['head'].unitsPerEm, isTTF=False)
    fb.setupGlyphOrder(names)
    fb.setupCharacterMap({u: rename[n] for u, n in tt.getBestCmap().items()})
    fb.setupCFF('TestCFF', {'FullName': 'Test CFF'}, charstrings, {})
    fb.setupHorizontalMetrics({rename[n]: hmtx[n] for n in order})
    hh = tt['hhea']
    fb.setupHorizontalHeader(ascent=hh.ascent, descent=hh.descent)
    fb.setupNameTable({'familyName': 'Test CFF', 'styleName': 'Regular'})
    fb.setupOS2()
    fb.setupPost()
    for t in ('GDEF', 'GSUB', 'GPOS'):
        if t in tt and not cid:
            fb.font[t] = tt[t]
    font = fb.font
    cff = font['CFF '].cff
    top = cff.topDictIndex[0]
    if subrs:
        _subroutinize(top, cff)
    if cid:
        _make_cid(top, cff, names)
    font.save(out)
    return out


def _program(cs):
    cs.decompile() if cs.program is None else None
    return list(cs.program)


def _subroutinize(top, cff):
    """Tails of charstrings ending in an operator become subroutines: odd glyphs' go to local
    Subrs, even ones' to the global ones; stems and a hint mask open every glyph."""
    rng = random.Random(1)
    priv = top.Private
    local, glob = [], []
    cs_index = top.CharStrings
    names = list(cs_index.keys())
    for k, name in enumerate(names):
        cs = cs_index[name]
        prog = _program(cs)
        # width first if any; stems and a mask after it
        width = []
        ops = [i for i, t in enumerate(prog) if isinstance(t, str)]
        if not ops:
            continue
        first_op = ops[0]
        args = prog[:first_op]
        if prog[first_op] in ('rmoveto',) and len(args) == 3 or prog[first_op] in ('hmoveto', 'vmoveto') and len(args) == 2:
            width, prog = [args[0]], prog[1:]
        elif prog[first_op] == 'endchar' and len(args) == 1:
            width, prog = [args[0]], prog[1:]
        nst = rng.randint(1, 3)
        stems = []
        for _ in range(nst):
            stems += [rng.randint(-50, 400), rng.randint(10, 80)]
        mask = [rng.randrange(256) for _ in range((2 * nst + 7) // 8)]
        head = width + stems + ['hstemhm'] + stems + ['hintmask', bytes(mask)]
        # the tail after the middle operator into a subroutine
        ops = [i for i, t in enumerate(prog) if isinstance(t, str)]
        if len(ops) < 3:
            cs.program = head + prog
            continue
        cut = ops[len(ops) // 2] + 1
        tail, prog = prog[cut:], prog[:cut]
        if tail and tail[-1] == 'endchar':
            tail = tail[:-1]
            end = ['endchar']
        else:
            end = []
        target = local if k % 2 else glob
        target.append(tail + ['return'])
        n = len(target) - 1
        cs.program = head + prog + [n, 'callsubr' if k % 2 else 'callgsubr'] + end
    lb = 107 if len(local) < 1240 else 1131 if len(local) < 33900 else 32768
    gb = 107 if len(glob) < 1240 else 1131 if len(glob) < 33900 else 32768
    for name in names:
        cs = cs_index[name]
        p = cs.program
        for i, t in enumerate(p):
            if t in ('callsubr', 'callgsubr') and isinstance(p[i - 1], int):
                p[i - 1] = p[i - 1] - (lb if t == 'callsubr' else gb)
    priv.Subrs = cffLib.SubrsIndex()
    for prog in local:
        priv.Subrs.append(T2CharString(program=prog))
    cff.GlobalSubrs.clear() if hasattr(cff.GlobalSubrs, 'clear') else None
    for prog in glob:
        cff.GlobalSubrs.append(T2CharString(program=prog))
    for name in names:
        cs_index[name].private = priv


def _make_cid(top, cff, order):
    """CID-keyed: ROS, two Font DICTs (the second with its own Private and Subrs), FDSelect."""
    priv = top.Private
    fdarray = cffLib.FDArrayIndex()
    for k in range(2):
        fd = cffLib.FontDict()
        fd.Private = priv
        fd.rawDict = {}
        fdarray.append(fd)
    top.ROS = ('Adobe', 'Identity', 0)
    top.CIDCount = len(order)
    top.FDArray = fdarray
    sel = cffLib.FDSelect()
    sel.format = 3
    sel.gidArray = [k % 2 for k in range(len(order))]
    top.FDSelect = sel
    del top.Private
    top.charset = order

#!/usr/bin/env python3
"""Generate layout/ucd.asm - the Unicode data lib/ufont's text shaping reads.

Usage: ucd_table.py <ucd directory>

The directory holds the Unicode 17.0.0 UnicodeData.txt, Scripts.txt,
DerivedNormalizationProps.txt, PropertyValueAliases.txt, emoji-data.txt,
ArabicShaping.txt and BidiMirroring.txt. Written:

- general category and modified combining class of every code point, and
  its script (an index into the script table), as three-level tables:
      ufl_ucd_gc(cp), ufl_ucd_mcc(cp), ufl_ucd_script(cp) -> eax
  General categories are numbered in HarfBuzz's order (Cc 0, Cf 1, Cn 2,
  ... Zs 29). The modified combining class reorders Hebrew, Arabic, Syriac,
  Telugu, Thai, Lao and Tibetan points the way fonts expect (as HarfBuzz
  does);
- canonical decompositions (ab -> a, b; b 0 for a singleton), sorted by ab;
- canonical compositions (a, b -> ab) of primary composites, sorted by a, b;
- per script: its ISO 15924 code and the OpenType script tags fonts use for
  it (the old tag, and for Indic scripts the new one: 'dev2' and so on);
- the Extended_Pictographic ranges (a ZWJ joins one to the grapheme before);
- Arabic joining types (U 0, L 1, R 2, D / C 3, Alaph 4, Dalath-Rish 5,
  T 7; characters not listed: T for Mn / Me / Cf, else U) and the bidi
  mirrored pairs;
- for Arabic fallback shaping (fonts with presentation forms but no
  Arabic GSUB): each letter's initial / medial / final / isolated form, and
  the lam-alef and other ligatures (two and three letters, shadda with a
  haraka) between those forms, from UnicodeData's presentation-form
  decompositions as HarfBuzz derives them;
  the last two lists also as tools/ucd_data.py for the model.

Hangul syllables are composed and decomposed arithmetically (layout code),
not listed.

Development-machine tooling only; not part of any OS image.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'layout', 'ucd.asm')

GC = ['Cc', 'Cf', 'Cn', 'Co', 'Cs', 'Ll', 'Lm', 'Lo', 'Lt', 'Lu', 'Mc', 'Me', 'Mn', 'Nd', 'Nl', 'No', 'Pc', 'Pd',
      'Pe', 'Pf', 'Pi', 'Po', 'Ps', 'Sc', 'Sk', 'Sm', 'So', 'Zl', 'Zp', 'Zs']
MCC = list(range(256))
MCC[10:27] = [22, 15, 16, 17, 23, 18, 19, 20, 21, 14, 24, 12, 25, 13, 10, 11, 26]
MCC[27:37] = [28, 29, 30, 31, 32, 33, 27, 34, 35, 36]
MCC[84], MCC[91], MCC[103], MCC[130], MCC[132] = 4, 5, 3, 132, 131
NEW_TAGS = {'Beng': 'bng2', 'Deva': 'dev2', 'Gujr': 'gjr2', 'Guru': 'gur2', 'Knda': 'knd2', 'Mlym': 'mlm2',
            'Orya': 'ory2', 'Taml': 'tml2', 'Telu': 'tel2', 'Mymr': 'mym2'}
OLD_SPECIAL = {'Hira': 'kana', 'Laoo': 'lao ', 'Yiii': 'yi  ', 'Nkoo': 'nko ', 'Vaii': 'vai '}
SHIFT1, SHIFT2 = 11, 6                      # 2048-code-point chunks of 64-code-point blocks


def ranges(path):
    for line in open(path, encoding='utf-8'):
        line = line.split('#')[0]
        f = [x.strip() for x in line.split(';')]
        if len(f) < 2:
            continue
        r = f[0].split('..')
        yield int(r[0], 16), int(r[-1], 16), f[1:]


def unicode_data(ucd):
    gc = [GC.index('Cn')] * 0x110000
    ccc = [0] * 0x110000
    decomp = {}
    first = None
    for line in open(os.path.join(ucd, 'UnicodeData.txt'), encoding='utf-8'):
        f = line.rstrip('\n').split(';')
        cp = int(f[0], 16)
        if f[1].endswith(', First>'):
            first = cp
            continue
        lo = first if f[1].endswith(', Last>') else cp
        first = None
        for u in range(lo, cp + 1):
            gc[u] = GC.index(f[2])
            ccc[u] = int(f[3])
        if f[5] and not f[5].startswith('<'):
            parts = [int(x, 16) for x in f[5].split()]
            decomp[cp] = (parts[0], parts[1] if len(parts) > 1 else 0)
    return gc, ccc, decomp


def trie(values, name, default):
    """Three levels: chunk index per 2048 code points, block index per 64, the values."""
    blocks, block_ids, chunks, chunk_ids, top = [], {}, [], {}, []
    bsize, csize = 1 << SHIFT2, 1 << (SHIFT1 - SHIFT2)
    for c0 in range(0, 0x110000, 1 << SHIFT1):
        chunk = []
        for b0 in range(c0, c0 + (1 << SHIFT1), bsize):
            blk = tuple(values[b0:b0 + bsize])
            if blk not in block_ids:
                block_ids[blk] = len(blocks)
                blocks.append(blk)
            chunk.append(block_ids[blk])
        chunk = tuple(chunk)
        if chunk not in chunk_ids:
            chunk_ids[chunk] = len(chunks)
            chunks.append(chunk)
        top.append(chunk_ids[chunk])
    out = [f'; {name}: {len(top)} chunks, {len(chunks)} distinct, {len(blocks)} blocks',
           f'{name}_1:']
    out += rows('dw', top)
    out.append(f'{name}_2:')
    out += rows('dw', [x for c in chunks for x in c])
    out.append(f'{name}_3:')
    out += rows('db', [x for b in blocks for x in b])
    return out


def rows(kind, vals, per=16):
    return [f'    {kind} ' + ', '.join(str(v) for v in vals[i:i + per]) for i in range(0, len(vals), per)]


def tag(s):
    return "'" + s + "'"


# the presentation-form ligatures Arabic fallback shaping makes (HarfBuzz's subset), and three
# private-use ones it adds
ARABIC_LIGATURES = (
    0xF2EE, 0xFC08, 0xFC0E, 0xFC12, 0xFC32, 0xFC3F, 0xFC40, 0xFC41, 0xFC42, 0xFC44, 0xFC4E, 0xFC5E, 0xFC60, 0xFC61,
    0xFC62, 0xFC6A, 0xFC6D, 0xFC6F, 0xFC70, 0xFC73, 0xFC75, 0xFC86, 0xFC8F, 0xFC91, 0xFC94, 0xFC9C, 0xFC9D, 0xFC9E,
    0xFC9F, 0xFCA1, 0xFCA2, 0xFCA3, 0xFCA4, 0xFCA8, 0xFCAA, 0xFCAC, 0xFCB0, 0xFCC9, 0xFCCA, 0xFCCB, 0xFCCC, 0xFCCD,
    0xFCCE, 0xFCCF, 0xFCD0, 0xFCD1, 0xFCD2, 0xFCD3, 0xFCD5, 0xFCDA, 0xFCDB, 0xFCDC, 0xFCDD, 0xFD30, 0xFD88, 0xFEF5,
    0xFEF6, 0xFEF7, 0xFEF8, 0xFEF9, 0xFEFA, 0xFEFB, 0xFEFC, 0xF201, 0xF211, 0xF2EE)
ARABIC_PUA = ["F201;PUA ARABIC LIGATURE LELLAH ISOLATED FORM;Lo;0;AL;<isolated> 0644 0644 0647;;;;N;;;;;",
              "F211;PUA ARABIC LIGATURE LAM WITH MEEM WITH JEEM INITIAL FORM;Lo;0;AL;<initial> 0644 0645 062C;;;;N;;;;;",
              "F2EE;PUA ARABIC LIGATURE SHADDA WITH FATHATAN ISOLATED FORM;Lo;0;AL;<isolated> 0020 064B 0651;;;;N;;;;;"]


def arabic_fallback(ucd):
    """-> (shapes {u: (initial, medial, final, isolated)}, 2-ligatures {first: [(second, lig)]}, mark
    ligatures {first: [(second, lig)]}, 3-ligatures {first: [(second, third, lig)]}), first and the
    components being presentation forms (marks: the characters)."""
    shapes, ligatures = {}, {}
    lines = open(os.path.join(ucd, 'UnicodeData.txt'), encoding='utf-8').read().splitlines() + ARABIC_PUA
    for line in lines:
        f = [x.strip() for x in line.split(';')]
        if f[5][0:1] != '<':
            continue
        items = f[5].split(' ')
        shape, items = items[0][1:-1], tuple(int(x, 16) for x in items[1:])
        c = int(f[0], 16)
        if shape not in ('initial', 'medial', 'isolated', 'final'):
            continue
        if len(items) != 1:
            if items[0] == 0x0020:                      # a mark ligature: visual order, a space first
                items = items[:0:-1]
                shape = None
            if c not in ARABIC_LIGATURES:
                continue
            ligatures.setdefault(items, {})[shape] = c
        else:
            shapes.setdefault(items[0], {})[shape] = c
    forms = {u: tuple(sh.get(k, 0) for k in ('initial', 'medial', 'final', 'isolated')) for u, sh in shapes.items()}
    l2, l3, lm = {}, {}, {}
    for key, by_shape in ligatures.items():
        for shape, c in by_shape.items():
            if len(key) == 3:
                if shape == 'isolated':
                    liga = (shapes[key[0]]['initial'], shapes[key[1]]['medial'], shapes[key[2]]['final'])
                elif shape == 'final':
                    liga = (shapes[key[0]]['medial'], shapes[key[1]]['medial'], shapes[key[2]]['final'])
                else:
                    liga = (shapes[key[0]]['initial'], shapes[key[1]]['medial'], shapes[key[2]]['medial'])
                l3.setdefault(liga[0], []).append((liga[1], liga[2], c))
            elif shape is None:
                lm.setdefault(key[0], []).append((key[1], c))
            else:
                if shape == 'isolated':
                    liga = (shapes[key[0]]['initial'], shapes[key[1]]['final'])
                elif shape == 'final':
                    liga = (shapes[key[0]]['medial'], shapes[key[1]]['final'])
                else:
                    liga = (shapes[key[0]]['initial'], shapes[key[1]]['medial'])
                l2.setdefault(liga[0], []).append((liga[1], c))
    return forms, l2, lm, l3


def main():
    ucd = sys.argv[1]
    gc, ccc, decomp = unicode_data(ucd)
    mcc = [MCC[c] for c in ccc]
    mcc[0x1A60] = mcc[0x0FC6] = 254
    mcc[0x0F39] = 127
    # only marks keep a class (HarfBuzz keeps it for marks alone)
    for u in range(0x110000):
        if GC[gc[u]] not in ('Mn', 'Mc', 'Me'):
            mcc[u] = 0
    aliases = {}
    for line in open(os.path.join(ucd, 'PropertyValueAliases.txt'), encoding='utf-8'):
        f = [x.strip() for x in line.split('#')[0].split(';')]
        if len(f) >= 3 and f[0] == 'sc':
            aliases[f[2]] = f[1]
            for extra in f[3:]:
                aliases[extra] = f[1]
    names = ['Zzzz', 'Zyyy', 'Zinh']               # unknown, common, inherited first
    script = [0] * 0x110000
    for lo, hi, (name, *_) in ranges(os.path.join(ucd, 'Scripts.txt')):
        iso = aliases[name]
        if iso not in names:
            names.append(iso)
        for u in range(lo, hi + 1):
            script[u] = names.index(iso)
    excluded = set()
    for lo, hi, (prop, *_) in ranges(os.path.join(ucd, 'DerivedNormalizationProps.txt')):
        if prop == 'Full_Composition_Exclusion':
            excluded.update(range(lo, hi + 1))
    comp = sorted((a, b, ab) for ab, (a, b) in decomp.items() if b and ab not in excluded)
    pict = []
    for lo, hi, (prop, *_) in ranges(os.path.join(ucd, 'emoji-data.txt')):
        if prop == 'Extended_Pictographic':
            if pict and pict[-1][1] + 1 == lo:
                pict[-1] = (pict[-1][0], hi)
            else:
                pict.append((lo, hi))
    joining = {}
    for line in open(os.path.join(ucd, 'ArabicShaping.txt'), encoding='utf-8'):
        f = [x.strip() for x in line.split('#')[0].split(';')]
        if len(f) < 4:
            continue
        t = {'U': 0, 'L': 1, 'R': 2, 'D': 3, 'C': 3, 'T': 7}[f[2]]
        if f[3] == 'ALAPH':
            t = 4
        elif f[3] == 'DALATH RISH':
            t = 5
        joining[int(f[0], 16)] = t
    mirror = {}
    for line in open(os.path.join(ucd, 'BidiMirroring.txt'), encoding='utf-8'):
        f = [x.strip() for x in line.split('#')[0].split(';')]
        if len(f) >= 2 and f[0]:
            mirror[int(f[0], 16)] = int(f[1], 16)
    out = ['; =============================================================================',
           '; Utkarsha OS — lib/ufont/layout/ucd.asm',
           '; =============================================================================',
           '; Unicode 17.0.0 data for text shaping, generated by tools/ucd_table.py from',
           '; UnicodeData.txt, Scripts.txt, DerivedNormalizationProps.txt and',
           '; PropertyValueAliases.txt; do not edit.',
           ';',
           ';   ufl_ucd_gc(edi = code point)     -> eax general category (HarfBuzz order: Cc 0',
           ';                                   ... Zs 29; Cn past the last code point)',
           ';   ufl_ucd_mcc(edi)                 -> eax modified combining class (marks only)',
           ';   ufl_ucd_script(edi)              -> eax script index (0 unknown, 1 common,',
           ';                                   2 inherited)',
           ';   ufl_ucd_scripts                  -> per script: dd ISO 15924 code, old',
           ';                                   OpenType tag, new tag (0: none)',
           ';   ufl_ucd_decomp, ufl_ucd_decomp_count -> dd ab, a, b (b 0: a singleton), by ab',
           ';   ufl_ucd_comp, ufl_ucd_comp_count     -> dd a, b, ab, by a then b',
           ';   ufl_ucd_pict, ufl_ucd_pict_count     -> dd first, last: Extended_Pictographic',
           ';   ufl_ucd_joining, ..._count   -> dd code point | joining type << 24, sorted',
           ';   ufl_ucd_mirror, ..._count    -> dd code point, its mirror, sorted',
           ';   ufl_ucd_arforms (_first, _last) -> per letter dw initial, medial,',
           ';                                   final, isolated presentation forms',
           ';   ufl_ucd_arlig3 / arlig2 / arligm -> Arabic fallback ligatures: dw first,',
           ';                                   count, then the rest and the ligature',
           '; =============================================================================',
           '',
           'section .text',
           '']
    for fn, name, default in (('ufl_ucd_gc', 'ucd_gct', GC.index('Cn')), ('ufl_ucd_mcc', 'ucd_mcct', 0),
                              ('ufl_ucd_script', 'ucd_sct', 0)):
        out += [f'global {fn}',
                f'{fn}:',
                '    mov eax, ' + str(default),
                '    cmp edi, 0x10FFFF',
                '    ja .out',
                '    mov eax, edi',
                f'    shr eax, {SHIFT1}',
                f'    lea rcx, [rel {name}_1]',
                '    movzx eax, word [rcx + rax * 2]',
                f'    shl eax, {SHIFT1 - SHIFT2}',
                '    mov edx, edi',
                f'    shr edx, {SHIFT2}',
                f'    and edx, {(1 << (SHIFT1 - SHIFT2)) - 1}',
                '    add eax, edx',
                f'    lea rcx, [rel {name}_2]',
                '    movzx eax, word [rcx + rax * 2]',
                f'    shl eax, {SHIFT2}',
                '    mov edx, edi',
                f'    and edx, {(1 << SHIFT2) - 1}',
                '    add eax, edx',
                f'    lea rcx, [rel {name}_3]',
                '    movzx eax, byte [rcx + rax]',
                '.out:',
                '    ret',
                '']
    out += ['section .rodata', 'align 4']
    out += trie(gc, 'ucd_gct', 2)
    out += trie(mcc, 'ucd_mcct', 0)
    out += trie(script, 'ucd_sct', 0)
    out += ['', 'align 4', 'global ufl_ucd_scripts', 'global ufl_ucd_scripts_count', 'ufl_ucd_scripts_count: dd ' + str(len(names)),
            'ufl_ucd_scripts:']
    for iso in names:
        if iso in ('Zzzz', 'Zyyy', 'Zinh'):
            old = 'DFLT'
        else:
            old = OLD_SPECIAL.get(iso, iso[0].lower() + iso[1:])
        new = NEW_TAGS.get(iso)
        out.append(f'    dd {tag(iso)}, {tag(old)}, {tag(new) if new else 0}')
    out += ['', 'global ufl_ucd_decomp', 'global ufl_ucd_decomp_count', f'ufl_ucd_decomp_count: dd {len(decomp)}', 'ufl_ucd_decomp:']
    for ab in sorted(decomp):
        a, b = decomp[ab]
        out.append(f'    dd 0x{ab:X}, 0x{a:X}, 0x{b:X}')
    out += ['', 'global ufl_ucd_comp', 'global ufl_ucd_comp_count', f'ufl_ucd_comp_count: dd {len(comp)}', 'ufl_ucd_comp:']
    for a, b, ab in comp:
        out.append(f'    dd 0x{a:X}, 0x{b:X}, 0x{ab:X}')
    out += ['', 'global ufl_ucd_pict', 'global ufl_ucd_pict_count', f'ufl_ucd_pict_count: dd {len(pict)}', 'ufl_ucd_pict:']
    for lo, hi in pict:
        out.append(f'    dd 0x{lo:X}, 0x{hi:X}')
    out += ['', 'global ufl_ucd_joining', 'global ufl_ucd_joining_count',
            f'ufl_ucd_joining_count: dd {len(joining)}', 'ufl_ucd_joining:']
    for u in sorted(joining):
        out.append(f'    dd 0x{u:X} | ({joining[u]} << 24)')
    out += ['', 'global ufl_ucd_mirror', 'global ufl_ucd_mirror_count',
            f'ufl_ucd_mirror_count: dd {len(mirror)}', 'ufl_ucd_mirror:']
    for u in sorted(mirror):
        out.append(f'    dd 0x{u:X}, 0x{mirror[u]:X}')
    lines = ['"""Unicode 17.0.0 data the shaping model needs beyond Python\'s unicodedata - generated by',
             'tools/ucd_table.py from emoji-data.txt, ArabicShaping.txt and BidiMirroring.txt; do not edit."""',
             'EXTENDED_PICTOGRAPHIC = [']
    lines += [f'    (0x{lo:X}, 0x{hi:X}),' for lo, hi in pict]
    lines.append(']')
    lines.append('JOINING = {')
    lines += [f'    0x{u:X}: {joining[u]},' for u in sorted(joining)]
    lines.append('}')
    lines.append('MIRROR = {')
    lines += [f'    0x{u:X}: 0x{mirror[u]:X},' for u in sorted(mirror)]
    lines.append('}')
    # Arabic fallback shaping
    forms, l2, lm, l3 = arabic_fallback(ucd)
    first, last = min(forms), max(forms)
    out += ['', 'global ufl_ucd_arforms', 'global ufl_ucd_arforms_first', 'global ufl_ucd_arforms_last',
            f'ufl_ucd_arforms_first: dd 0x{first:X}', f'ufl_ucd_arforms_last: dd 0x{last:X}',
            'ufl_ucd_arforms:                       ; initial, medial, final, isolated']
    for u in range(first, last + 1):
        out.append('    dw ' + ', '.join(f'0x{x:X}' for x in forms.get(u, (0, 0, 0, 0))))
    for name, table, n in (('ufl_ucd_arlig3', l3, 3), ('ufl_ucd_arlig2', l2, 2), ('ufl_ucd_arligm', lm, 2)):
        out += ['', f'global {name}', f'{name}:                    ; first, count, then (components, ligature)']
        for f0 in sorted(table):
            out.append(f'    dw 0x{f0:X}, {len(table[f0])}')
            for t in table[f0]:
                out.append('    dw ' + ', '.join(f'0x{x:X}' for x in t))
        out.append('    dw 0')
    lines.append('ARABIC_FORMS = {')
    lines += [f'    0x{u:X}: {tuple(forms[u])},' for u in sorted(forms)]
    lines.append('}')
    for name, table in (('ARABIC_LIG3', l3), ('ARABIC_LIG2', l2), ('ARABIC_LIGM', lm)):
        lines.append(f'{name} = {{')
        lines += [f'    0x{f0:X}: {table[f0]!r},' for f0 in sorted(table)]
        lines.append('}')
    open(os.path.join(HERE, 'ucd_data.py'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(f'{len(names)} scripts, {len(decomp)} decompositions, {len(comp)} compositions')


if __name__ == '__main__':
    main()

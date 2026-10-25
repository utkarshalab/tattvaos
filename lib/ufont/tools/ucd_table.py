#!/usr/bin/env python3
"""Generate layout/ucd.asm - the Unicode data lib/ufont's text shaping reads.

Usage: ucd_table.py <ucd directory>

The directory holds the Unicode 17.0.0 UnicodeData.txt, Scripts.txt,
DerivedNormalizationProps.txt and PropertyValueAliases.txt. Written:

- general category and modified combining class of every code point, and
  its script (an index into the script table), as three-level tables:
      ucd_gc(cp), ucd_mcc(cp), ucd_script(cp) -> eax
  General categories are numbered in HarfBuzz's order (Cc 0, Cf 1, Cn 2,
  ... Zs 29). The modified combining class reorders Hebrew, Arabic, Syriac,
  Telugu, Thai, Lao and Tibetan points the way fonts expect (as HarfBuzz
  does);
- canonical decompositions (ab -> a, b; b 0 for a singleton), sorted by ab;
- canonical compositions (a, b -> ab) of primary composites, sorted by a, b;
- per script: its ISO 15924 code and the OpenType script tags fonts use for
  it (the old tag, and for Indic scripts the new one: 'dev2' and so on).

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
    out = ['; =============================================================================',
           '; Utkarsha OS — lib/ufont/layout/ucd.asm',
           '; =============================================================================',
           '; Unicode 17.0.0 data for text shaping, generated by tools/ucd_table.py from',
           '; UnicodeData.txt, Scripts.txt, DerivedNormalizationProps.txt and',
           '; PropertyValueAliases.txt; do not edit.',
           ';',
           ';   ucd_gc(edi = code point)     -> eax general category (HarfBuzz order: Cc 0',
           ';                                   ... Zs 29; Cn past the last code point)',
           ';   ucd_mcc(edi)                 -> eax modified combining class (marks only)',
           ';   ucd_script(edi)              -> eax script index (0 unknown, 1 common,',
           ';                                   2 inherited)',
           ';   ucd_scripts                  -> per script: dd ISO 15924 code, old',
           ';                                   OpenType tag, new tag (0: none)',
           ';   ucd_decomp, ucd_decomp_count -> dd ab, a, b (b 0: a singleton), by ab',
           ';   ucd_comp, ucd_comp_count     -> dd a, b, ab, by a then b',
           '; =============================================================================',
           '',
           'section .text',
           '']
    for fn, name, default in (('ucd_gc', 'ucd_gct', GC.index('Cn')), ('ucd_mcc', 'ucd_mcct', 0),
                              ('ucd_script', 'ucd_sct', 0)):
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
    out += ['', 'align 4', 'global ucd_scripts', 'global ucd_scripts_count', 'ucd_scripts_count: dd ' + str(len(names)),
            'ucd_scripts:']
    for iso in names:
        if iso in ('Zzzz', 'Zyyy', 'Zinh'):
            old = 'DFLT'
        else:
            old = OLD_SPECIAL.get(iso, iso[0].lower() + iso[1:])
        new = NEW_TAGS.get(iso)
        out.append(f'    dd {tag(iso)}, {tag(old)}, {tag(new) if new else 0}')
    out += ['', 'global ucd_decomp', 'global ucd_decomp_count', f'ucd_decomp_count: dd {len(decomp)}', 'ucd_decomp:']
    for ab in sorted(decomp):
        a, b = decomp[ab]
        out.append(f'    dd 0x{ab:X}, 0x{a:X}, 0x{b:X}')
    out += ['', 'global ucd_comp', 'global ucd_comp_count', f'ucd_comp_count: dd {len(comp)}', 'ucd_comp:']
    for a, b, ab in comp:
        out.append(f'    dd 0x{a:X}, 0x{b:X}, 0x{ab:X}')
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(f'{len(names)} scripts, {len(decomp)} decompositions, {len(comp)} compositions')


if __name__ == '__main__':
    main()

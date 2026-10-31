#!/usr/bin/env python3
"""Generate the Universal Shaping Engine's character categories: tools/use_data.py for the model
and layout/use_table.asm for lib/ufont.

Usage: use_table.py <ucd directory> <ms-use directory>

The UCD directory holds IndicSyllabicCategory.txt, IndicPositionalCategory.txt,
ArabicShaping.txt, DerivedCoreProperties.txt, UnicodeData.txt, Blocks.txt and Scripts.txt
(Unicode 17.0.0); the ms-use one Microsoft's IndicSyllabicCategory-Additional.txt and
IndicPositionalCategory-Additional.txt overrides (as HarfBuzz carries them). Each character
gets its USE category by HarfBuzz's rules (gen-use-table.py): the Indic syllabic category
(with the overrides and a few corrections), general category, joining type and whether it is
default ignorable pick one of B, N, GB, CGJ, F, FM, M, CM, SUB, CS, H, HVM, HN, IS, G, HM, HR, J,
SB, SE, ZWNJ, O, RK, R, Sk, SM, V, VM, WJ; finals, medials, modifiers and vowels then take
their position (Abv, Blw, Pst, Pre) from the Indic positional category. Thai, Lao, Arabic,
Syriac and Samaritan are left out (their own shapers). Categories are HarfBuzz's numbers.

layout/use_table.asm:

    ufl_use_ranges, ufl_use_ranges_count    dd first, last; db category, 0, 0, 0
                                            (sorted; code points not covered are O)

    ufl_use_vowels                          per script: dd ISO tag, pairs; then dd vowel, sign
                                            per pair (tools/vowel_data.py); dd 0 ends it

and the USE grammar (tools/use.py) compiled to a DFA as ufl_use_machine (layout/syllabic.asm).

Development-machine tooling only; not part of any OS image.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# HarfBuzz's category numbers (hb-ot-shaper-use-machine.rl)
CATEGORIES = {'O': 0, 'B': 1, 'N': 4, 'GB': 5, 'CGJ': 6, 'SUB': 11, 'H': 12, 'HN': 13, 'ZWNJ': 14, 'WJ': 16,
              'R': 18, 'CS': 43, 'IS': 44, 'Sk': 48, 'G': 49, 'J': 50, 'SB': 51, 'SE': 52, 'HVM': 53, 'HM': 54,
              'HR': 55, 'RK': 56, 'FAbv': 24, 'FBlw': 25, 'FPst': 26, 'MAbv': 27, 'MBlw': 28, 'MPst': 29,
              'MPre': 30, 'CMAbv': 31, 'CMBlw': 32, 'VAbv': 33, 'VBlw': 34, 'VPst': 35, 'VPre': 22, 'VMAbv': 37,
              'VMBlw': 38, 'VMPst': 39, 'VMPre': 23, 'SMAbv': 41, 'SMBlw': 42, 'FMAbv': 45, 'FMBlw': 46,
              'FMPst': 47}
DISABLED_SCRIPTS = {'Arabic', 'Lao', 'Samaritan', 'Syriac', 'Thai'}
DEFAULTS = ('Other', 'Not_Applicable', 'jt_X', '', 'Cn', 'No_Block', 'Unknown')

# where a category's position comes from: {category: {suffix: positional categories}}
POSITIONS = {
    'F': {'Abv': ['Top'], 'Blw': ['Bottom'], 'Pst': ['Right']},
    'M': {'Abv': ['Top'], 'Blw': ['Bottom', 'Bottom_And_Left', 'Bottom_And_Right'], 'Pst': ['Right'],
          'Pre': ['Left', 'Top_And_Bottom_And_Left']},
    'CM': {'Abv': ['Top'], 'Blw': ['Bottom', 'Overstruck']},
    'V': {'Abv': ['Top', 'Top_And_Bottom', 'Top_And_Bottom_And_Right', 'Top_And_Right'],
          'Blw': ['Bottom', 'Overstruck', 'Bottom_And_Right'], 'Pst': ['Right'],
          'Pre': ['Left', 'Top_And_Left', 'Top_And_Left_And_Right', 'Left_And_Right']},
    'VM': {'Abv': ['Top'], 'Blw': ['Bottom', 'Overstruck'], 'Pst': ['Right'], 'Pre': ['Left']},
    'SM': {'Abv': ['Top'], 'Blw': ['Bottom']},
    'FM': {'Abv': ['Top'], 'Blw': ['Bottom'], 'Pst': ['Not_Applicable']},
}
NO_POSITION = ('H', 'HM', 'HR', 'HVM', 'IS', 'B', 'R', 'RK', 'SUB')


def parse(path, field, skip_header, only=None):
    """{code point: value} from a UCD-style file (field: which ; field holds the value; only: the
    one value kept)."""
    out = {}
    lines = open(path, encoding='utf-8')
    if skip_header:
        for line in lines:                              # the overrides' header runs to a blank line
            if not line.strip():
                break
    for line in lines:
        line = line.split('#')[0]
        f = [x.strip() for x in line.split(';')]
        if len(f) == 1:
            continue
        if only is not None and f[field] != only:
            continue
        r = f[0].split('..')
        for u in range(int(r[0], 16), int(r[-1], 16) + 1):
            out[u] = f[field]
    return out


def is_base(u, isc, di, gc, jt):
    return (isc in ('Number', 'Consonant', 'Consonant_Head_Letter', 'Tone_Letter', 'Vowel_Independent') or
            jt in ('jt_C', 'jt_D', 'jt_L', 'jt_R') and isc != 'Joiner' or
            gc == 'Lo' and isc in ('Avagraha', 'Bindu', 'Consonant_Final', 'Consonant_Medial',
                                   'Consonant_Subjoined', 'Vowel', 'Vowel_Dependent'))


def is_base_other(u, isc, di, gc, jt):
    return isc == 'Consonant_Placeholder' or u in (0x2015, 0x2022, 0x25FB, 0x25FC, 0x25FD, 0x25FE)


def is_cgj(u, isc, di, gc, jt):
    return isc == 'Joiner' or bool(di) and gc in ('Mc', 'Me', 'Mn')


def is_sakot(u, isc, di, gc, jt):
    return u == 0x1A60


def is_sym_mod(u, isc, di, gc, jt):
    return isc == 'Symbol_Modifier'


def is_word_joiner(u, isc, di, gc, jt):
    return (bool(di) and u not in (0x115F, 0x1160, 0x3164, 0xFFA0, 0x1BCA0, 0x1BCA1, 0x1BCA2, 0x1BCA3) and
            isc == 'Other' and not is_cgj(u, isc, di, gc, jt)) or gc == 'Cn'


def is_other(u, isc, di, gc, jt):
    return ((gc == 'Po' or isc in ('Consonant_Dead', 'Joiner', 'Modifying_Letter', 'Other')) and
            not is_base(u, isc, di, gc, jt) and not is_base_other(u, isc, di, gc, jt) and
            not is_cgj(u, isc, di, gc, jt) and not is_sym_mod(u, isc, di, gc, jt) and
            not is_word_joiner(u, isc, di, gc, jt))


RULES = {
    'B': is_base,
    'N': lambda u, isc, di, gc, jt: isc == 'Brahmi_Joining_Number',
    'GB': is_base_other,
    'CGJ': is_cgj,
    'F': lambda u, isc, di, gc, jt: isc == 'Consonant_Final' and gc != 'Lo' or isc == 'Consonant_Succeeding_Repha',
    'FM': lambda u, isc, di, gc, jt: isc == 'Syllable_Modifier',
    'M': lambda u, isc, di, gc, jt: isc == 'Consonant_Medial' and gc != 'Lo' or isc == 'Consonant_Initial_Postfixed',
    'CM': lambda u, isc, di, gc, jt: isc in ('Nukta', 'Gemination_Mark', 'Consonant_Killer'),
    'SUB': lambda u, isc, di, gc, jt: isc == 'Consonant_Subjoined' and gc != 'Lo',
    'CS': lambda u, isc, di, gc, jt: isc == 'Consonant_With_Stacker',
    'H': lambda u, isc, di, gc, jt: isc == 'Virama' and u != 0x0DCA,
    'HVM': lambda u, isc, di, gc, jt: u == 0x0DCA,
    'HN': lambda u, isc, di, gc, jt: isc == 'Number_Joiner',
    'IS': lambda u, isc, di, gc, jt: isc == 'Invisible_Stacker' and u != 0x1A60,
    'G': lambda u, isc, di, gc, jt: isc == 'Hieroglyph',
    'HM': lambda u, isc, di, gc, jt: isc == 'Hieroglyph_Modifier',
    'HR': lambda u, isc, di, gc, jt: isc == 'Hieroglyph_Mirror',
    'J': lambda u, isc, di, gc, jt: isc == 'Hieroglyph_Joiner',
    'SB': lambda u, isc, di, gc, jt: isc in ('Hieroglyph_Mark_Begin', 'Hieroglyph_Segment_Begin'),
    'SE': lambda u, isc, di, gc, jt: isc in ('Hieroglyph_Mark_End', 'Hieroglyph_Segment_End'),
    'ZWNJ': lambda u, isc, di, gc, jt: isc == 'Non_Joiner',
    'O': is_other,
    'RK': lambda u, isc, di, gc, jt: isc == 'Reordering_Killer',
    'R': lambda u, isc, di, gc, jt: isc in ('Consonant_Preceding_Repha', 'Consonant_Prefixed'),
    'Sk': is_sakot,
    'SM': is_sym_mod,
    'V': lambda u, isc, di, gc, jt: isc == 'Pure_Killer' or gc != 'Lo' and isc in ('Vowel', 'Vowel_Dependent'),
    'VM': lambda u, isc, di, gc, jt: isc in ('Tone_Mark', 'Cantillation_Mark', 'Register_Shifter', 'Visarga') or
    gc != 'Lo' and isc == 'Bindu',
    'WJ': is_word_joiner,
}


def table(ucd, msuse):
    """{code point: category name} for every character the USE data covers (O included)."""
    j = lambda p: os.path.join(ucd, p)  # noqa: E731
    isc = parse(j('IndicSyllabicCategory.txt'), 1, False)
    ipc = parse(j('IndicPositionalCategory.txt'), 1, False)
    jt = {u: 'jt_' + v for u, v in parse(j('ArabicShaping.txt'), 2, False).items()}
    di = parse(j('DerivedCoreProperties.txt'), 1, False, 'Default_Ignorable_Code_Point')
    gc = parse(j('UnicodeData.txt'), 2, False)
    blocks = parse(j('Blocks.txt'), 1, False)
    scripts = parse(j('Scripts.txt'), 1, False)
    isc_add = {u: ('Syllable_Modifier' if v == 'Consonant_Final_Modifier' else v)
               for u, v in parse(os.path.join(msuse, 'IndicSyllabicCategory-Additional.txt'), 1, True).items()}
    ipc_add = {u: ('Not_Applicable' if v == 'NA' else v)
               for u, v in parse(os.path.join(msuse, 'IndicPositionalCategory-Additional.txt'), 1, True).items()}
    isc.update(isc_add)
    ipc.update(ipc_add)
    # the characters: those with any of the first four properties
    combined = {}
    for i, d in enumerate((isc, ipc, jt, di)):
        for u, v in d.items():
            combined.setdefault(u, list(DEFAULTS))[i] = v
    for i, d in ((4, gc), (5, blocks), (6, scripts)):
        for u, v in d.items():
            if u in combined:
                combined[u][i] = v
    out = {}
    for u, (cat, pos, joining, ignorable, general, _, script) in combined.items():
        if script in DISABLED_SCRIPTS:
            continue
        if 0x1CE2 <= u <= 0x1CE8:
            cat = 'Cantillation_Mark'
        if 0x0F18 <= u <= 0x0F19 or 0x0F3E <= u <= 0x0F3F:
            cat = 'Vowel_Dependent'
        if u == 0x1CED:
            cat = 'Tone_Mark'
        use = [k for k, rule in RULES.items() if rule(u, cat, ignorable, general, joining)]
        assert len(use) == 1, (hex(u), cat, use)
        use = use[0]
        if u in (0x11302, 0x11303, 0x114C1):
            pos = 'Top'
        assert pos in ('Not_Applicable', 'Visual_Order_Left') or u in (0x0F7F, 0x11A3A) or \
            use in POSITIONS or use in NO_POSITION, (hex(u), pos, use)
        if use in POSITIONS:
            suffix = [k for k, v in POSITIONS[use].items() if pos in v]
            assert len(suffix) == 1, (hex(u), pos, use)
            use += suffix[0]
        out[u] = use
    return out


def main():
    t = table(sys.argv[1], sys.argv[2])
    cats = {u: CATEGORIES[v] for u, v in t.items() if v != 'O'}
    lines = ['"""Universal Shaping Engine categories by code point - generated by tools/use_table.py from the',
             'Unicode 17.0.0 data and the ms-use overrides; do not edit.',
             '',
             'TABLE: {code point: USE category (HarfBuzz\'s numbers)}; characters not listed are O (0)."""',
             'TABLE = {']
    for u in sorted(cats):
        lines.append(f'    0x{u:04X}: {cats[u]},')
    lines.append('}')
    open(os.path.join(HERE, 'use_data.py'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    ranges = []
    for u in sorted(cats):
        if ranges and ranges[-1][1] == u - 1 and ranges[-1][2] == cats[u]:
            ranges[-1][1] = u
        else:
            ranges.append([u, u, cats[u]])
    print(f'{len(cats)} characters, {len(ranges)} ranges')
    sys.path.insert(0, HERE)
    import use                                  # the grammar
    classes, trans, accept = use.MACHINE
    assert len(trans) < 255
    out = ['; =============================================================================',
           '; Utkarsha OS — lib/ufont/layout/use_table.asm',
           '; =============================================================================',
           "; The Universal Shaping Engine's character categories and syllable automaton,",
           '; generated by tools/use_table.py (Unicode 17.0.0, the ms-use overrides, the',
           '; grammar of tools/use.py); do not edit. See that tool for the layout.',
           '; =============================================================================',
           '',
           'section .rodata',
           'align 8',
           'global ufl_use_ranges', 'global ufl_use_ranges_count', 'global ufl_use_machine', 'global ufl_use_vowels',
           f'ufl_use_ranges_count: dd {len(ranges)}',
           'ufl_use_ranges:']
    for a, b, c in ranges:
        out.append(f'    dd 0x{a:04X}, 0x{b:04X}')
        out.append(f'    db {c}, 0, 0, 0')
    from vowel_data import VOWEL_CONSTRAINTS
    out += ['', 'ufl_use_vowels:']
    for tag, pairs in VOWEL_CONSTRAINTS.items():
        out.append(f"    dd '{tag}', {len(pairs)}")
        for i in range(0, len(pairs), 4):
            out.append('    dd ' + ', '.join(f'0x{a:04X}, 0x{b:04X}' for a, b in pairs[i:i + 4]))
    out.append('    dd 0')
    out += ['', 'align 8', 'ufl_use_machine:', '    dq ufl_use_classes, ufl_use_dfa, ufl_use_accept',
            f'    dd {len(trans[0])}, {use.BROKEN_CLUSTER}', 'ufl_use_classes:']
    cls = [classes.get(c, 0) for c in range(64)]
    out += ['    db ' + ', '.join(str(v) for v in cls[i:i + 16]) for i in range(0, 64, 16)]
    out.append('ufl_use_dfa:')
    for row in trans:
        out.append('    db ' + ', '.join(str(v if v >= 0 else 255) for v in row))
    out.append('ufl_use_accept:')
    acc = [a if a >= 0 else 255 for a in accept]
    out += ['    db ' + ', '.join(str(v) for v in acc[i:i + 16]) for i in range(0, len(acc), 16)]
    path = os.path.join(HERE, '..', 'layout', 'use_table.asm')
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(f'{len(trans)} automaton states')


if __name__ == '__main__':
    main()

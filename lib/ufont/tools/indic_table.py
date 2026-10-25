#!/usr/bin/env python3
"""Generate the Indic shaper's tables: tools/indic_data.py for the model and
layout/indic_table.asm for lib/ufont.

Usage: indic_table.py <ucd directory>

The directory holds IndicSyllabicCategory.txt, IndicPositionalCategory.txt and
Blocks.txt (Unicode 17.0.0). Each character gets the syllable category the
syllable grammar reads and the position initial reordering sorts by, by the
rules HarfBuzz's Indic shaper uses, so the two shape alike:

- the Unicode syllabic category maps onto the grammar's categories (Bindu and
  Visarga are syllable modifiers, those with no position SMPst; Avagraha is a
  symbol; ...), then per-character corrections (Ra for the scripts' RA, the
  Vedic tone marks and symbols, ...);
- only modifiers, halants and matras keep a position; consonants (and vowels,
  placeholders, the dotted circle) are base consonants, modifiers and Vedic
  signs SMVD, and matras move to their script's reordering slot (Devanagari
  right, top and bottom matras after the subjoined consonants, left ones
  before the base).

Categories of the Khmer and Myanmar shapers the Indic grammar does not know
are written as X, which is what the Indic grammar makes of them.

layout/indic_table.asm also carries the syllable grammar of tools/indic.py
compiled to a DFA (tools/syllable.py):

    indic_chars, indic_chars_count  dd code point, db category, position, 0, 0
                                    (sorted; characters not listed: X / END)
    indic_classes                   db the grammar's class of categories 0 .. 63
    indic_dfa, indic_dfa_classes    db next state per state and class (0xFF: none)
    indic_accept                    db the syllable type a match ending in a state
                                    has (0xFF: none)

Development-machine tooling only; not part of any OS image.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

CATEGORIES = {'X': 0, 'C': 1, 'V': 2, 'N': 3, 'H': 4, 'ZWNJ': 5, 'ZWJ': 6, 'M': 7, 'SM': 8, 'A': 9, 'VD': 9,
              'PLACEHOLDER': 10, 'DOTTEDCIRCLE': 11, 'RS': 12, 'MPst': 13, 'Repha': 14, 'Ra': 15, 'CM': 16,
              'Symbol': 17, 'CS': 18, 'SMPst': 57}
POSITIONS = {'START': 0, 'RA_TO_BECOME_REPH': 1, 'PRE_M': 2, 'PRE_C': 3, 'BASE_C': 4, 'AFTER_MAIN': 5,
             'ABOVE_C': 6, 'BEFORE_SUB': 7, 'BELOW_C': 8, 'AFTER_SUB': 9, 'BEFORE_POST': 10, 'POST_C': 11,
             'AFTER_POST': 12, 'SMVD': 13, 'END': 14}

SINGLES = [0x00A0, 0x25CC]
BLOCKS = ['Basic Latin', 'Latin-1 Supplement', 'Devanagari', 'Bengali', 'Gurmukhi', 'Gujarati', 'Oriya', 'Tamil',
          'Telugu', 'Kannada', 'Malayalam', 'Myanmar', 'Khmer', 'Vedic Extensions', 'General Punctuation',
          'Superscripts and Subscripts', 'Devanagari Extended', 'Myanmar Extended-B', 'Myanmar Extended-A',
          'Myanmar Extended-C']
# the ranges the shaper looks up; everything else is X / END
RANGES = [(0x0028, 0x003F), (0x00B0, 0x00D7), (0x0900, 0x0D7F), (0x1000, 0x109F), (0x1780, 0x17EF),
          (0x1CD0, 0x1CFF), (0x2008, 0x2027), (0x2070, 0x2087), (0x25F8, 0x25FF), (0xA8E0, 0xA8FF),
          (0xA9E0, 0xA9FF), (0xAA60, 0xAA7F), (0xFE00, 0xFE0F), (0x11300, 0x11307), (0x11338, 0x1133F),
          (0x116D0, 0x116E7)]

CATEGORY_MAP = {
    'Other': 'X', 'Avagraha': 'Symbol', 'Bindu': 'SM', 'Brahmi_Joining_Number': 'PLACEHOLDER',
    'Cantillation_Mark': 'A', 'Consonant': 'C', 'Consonant_Dead': 'C', 'Consonant_Final': 'CM',
    'Consonant_Head_Letter': 'C', 'Consonant_Initial_Postfixed': 'C', 'Consonant_Killer': 'M',
    'Consonant_Medial': 'CM', 'Consonant_Placeholder': 'PLACEHOLDER', 'Consonant_Preceding_Repha': 'Repha',
    'Consonant_Prefixed': 'X', 'Consonant_Subjoined': 'CM', 'Consonant_Succeeding_Repha': 'CM',
    'Consonant_With_Stacker': 'CS', 'Gemination_Mark': 'SM', 'Invisible_Stacker': 'H', 'Joiner': 'ZWJ',
    'Modifying_Letter': 'X', 'Non_Joiner': 'ZWNJ', 'Nukta': 'N', 'Number': 'PLACEHOLDER',
    'Number_Joiner': 'PLACEHOLDER', 'Pure_Killer': 'M', 'Register_Shifter': 'RS', 'Syllable_Modifier': 'SM',
    'Tone_Letter': 'X', 'Tone_Mark': 'N', 'Virama': 'H', 'Visarga': 'SM', 'Vowel': 'V', 'Vowel_Dependent': 'M',
    'Vowel_Independent': 'V'}
POSITION_MAP = {
    'Not_Applicable': 'END', 'Left': 'PRE_C', 'Top': 'ABOVE_C', 'Bottom': 'BELOW_C', 'Right': 'POST_C',
    'Bottom_And_Right': 'POST_C', 'Left_And_Right': 'POST_C', 'Top_And_Bottom': 'BELOW_C',
    'Top_And_Bottom_And_Left': 'BELOW_C', 'Top_And_Bottom_And_Right': 'POST_C', 'Top_And_Left': 'ABOVE_C',
    'Top_And_Left_And_Right': 'POST_C', 'Top_And_Right': 'POST_C', 'Overstruck': 'AFTER_MAIN',
    'Visual_order_left': 'PRE_M'}

CATEGORY_OVERRIDES = {}
CATEGORY_OVERRIDES.update({u: 'VS' for u in range(0xFE00, 0xFE10)})
CATEGORY_OVERRIDES.update({u: 'PLACEHOLDER' for u in (0x2015, 0x2022, 0x25FB, 0x25FC, 0x25FD, 0x25FE)})
CATEGORY_OVERRIDES.update({u: 'Ra' for u in (0x0930, 0x09B0, 0x09F0, 0x0A30, 0x0AB0, 0x0B30, 0x0BB0, 0x0C30,
                                             0x0CB0, 0x0D30)})
CATEGORY_OVERRIDES.update({0x0953: 'SM', 0x0954: 'SM', 0x0A40: 'MPst', 0x0A72: 'C', 0x0A73: 'C', 0x1CF5: 'C',
                           0x1CF6: 'C', 0x1CED: 'A', 0x0A51: 'M', 0x11301: 'SM', 0x11302: 'SM', 0x11303: 'SM',
                           0x1133B: 'N', 0x1133C: 'N', 0x0AFB: 'N', 0x0B55: 'N', 0x09FC: 'PLACEHOLDER',
                           0x0C80: 'PLACEHOLDER', 0x0D04: 'PLACEHOLDER', 0x25CC: 'DOTTEDCIRCLE'})
CATEGORY_OVERRIDES.update({u: 'A' for u in range(0x1CE2, 0x1CE9)})
CATEGORY_OVERRIDES.update({u: 'Symbol' for u in list(range(0xA8F2, 0xA8F8)) + [0x1CE9, 0x1CEA, 0x1CEB, 0x1CEC,
                                                                              0x1CEE, 0x1CEF, 0x1CF0, 0x1CF1]})
# Khmer and Myanmar (their own shapers; here only what the Indic grammar sees)
CATEGORY_OVERRIDES.update({0x179A: 'Ra', 0x17CC: 'Robatic', 0x17C9: 'Robatic', 0x17CA: 'Robatic',
                           0x17D9: 'PLACEHOLDER', 0x104E: 'C', 0x1004: 'Ra', 0x101B: 'Ra', 0x105A: 'Ra',
                           0x1032: 'A', 0x1036: 'A', 0x103A: 'As', 0x103E: 'MH', 0x1060: 'ML', 0x103C: 'MR',
                           0x103D: 'MW', 0x1082: 'MW', 0x103B: 'MY', 0x105E: 'MY', 0x105F: 'MY', 0xAA7B: 'PT',
                           0x104A: 'PLACEHOLDER'})
CATEGORY_OVERRIDES.update({u: 'Xgroup' for u in (0x17C6, 0x17CB, 0x17CD, 0x17CE, 0x17CF, 0x17D0, 0x17D1)})
CATEGORY_OVERRIDES.update({u: 'Ygroup' for u in (0x17C7, 0x17C8, 0x17DD, 0x17D3)})
CATEGORY_OVERRIDES.update({u: 'PT' for u in (0x1063, 0x1064, 0x1069, 0x106A, 0x106B, 0x106C, 0x106D)})
CATEGORY_OVERRIDES.update({u: 'SM' for u in (0x1038, 0x1087, 0x1088, 0x1089, 0x108A, 0x108B, 0x108C, 0x108D,
                                             0x108F, 0x109A, 0x109B, 0x109C)})
POSITION_OVERRIDES = {0x0A51: 'BELOW_C', 0x0B01: 'BEFORE_SUB'}

POSITIONED = ('CM', 'SM', 'RS', 'H', 'M', 'MPst')
CONSONANTS = ('C', 'CS', 'Ra', 'CM', 'V', 'PLACEHOLDER', 'DOTTEDCIRCLE')
MATRAS = ('M', 'MPst')
SMVD = ('SM', 'SMPst', 'VD', 'A', 'Symbol')


def matra_position(u, pos, block):
    """Where a matra of a script sorts in initial reordering."""
    if pos == 'PRE_C':
        return 'PRE_M'
    if pos == 'POST_C':
        return {'Devanagari': 'AFTER_SUB', 'Bengali': 'AFTER_POST', 'Gurmukhi': 'AFTER_POST',
                'Gujarati': 'AFTER_POST', 'Oriya': 'AFTER_POST', 'Tamil': 'AFTER_POST',
                'Telugu': 'BEFORE_SUB' if u <= 0x0C42 else 'AFTER_SUB',
                'Kannada': 'BEFORE_SUB' if u < 0x0CC3 or u > 0x0CD6 else 'AFTER_SUB',
                'Malayalam': 'AFTER_POST'}.get(block, 'AFTER_SUB')
    if pos == 'ABOVE_C':
        return {'Devanagari': 'AFTER_SUB', 'Gurmukhi': 'AFTER_POST', 'Gujarati': 'AFTER_SUB',
                'Oriya': 'AFTER_MAIN', 'Tamil': 'AFTER_SUB', 'Telugu': 'BEFORE_SUB',
                'Kannada': 'BEFORE_SUB'}.get(block, 'AFTER_SUB')
    if pos == 'BELOW_C':
        return {'Devanagari': 'AFTER_SUB', 'Bengali': 'AFTER_SUB', 'Gurmukhi': 'AFTER_POST',
                'Gujarati': 'AFTER_POST', 'Oriya': 'AFTER_SUB', 'Tamil': 'AFTER_POST', 'Telugu': 'BEFORE_SUB',
                'Kannada': 'BEFORE_SUB', 'Malayalam': 'AFTER_POST'}.get(block, 'AFTER_SUB')
    raise ValueError(pos)


def read(path):
    d = {}
    for line in open(path, encoding='utf-8'):
        line = line.split('#')[0]
        f = [x.strip() for x in line.split(';')]
        if len(f) < 2:
            continue
        r = f[0].split('..')
        for u in range(int(r[0], 16), int(r[-1], 16) + 1):
            d[u] = f[1]
    return d


def table(ucd):
    """{code point: (category number, position number)} for every character not X / END."""
    syl = read(os.path.join(ucd, 'IndicSyllabicCategory.txt'))
    pos = read(os.path.join(ucd, 'IndicPositionalCategory.txt'))
    blocks = read(os.path.join(ucd, 'Blocks.txt'))
    combined = {}
    for i, d in enumerate((syl, pos)):
        for u, v in d.items():
            combined.setdefault(u, ['Other', 'Not_Applicable', 'No_Block'])[i] = v
    for u in combined:
        combined[u][2] = blocks.get(u, 'No_Block')
    combined = {u: v for u, v in combined.items() if u in SINGLES or v[2] in BLOCKS}
    data = {}
    for u, (cat, p, block) in combined.items():
        cat = CATEGORY_MAP[cat]
        if cat == 'SM' and p == 'Not_Applicable':
            cat = 'SMPst'
        data[u] = [cat, POSITION_MAP[p], block]
    for u, cat in CATEGORY_OVERRIDES.items():
        old = data.get(u, ['X', 'END', None])
        data[u] = [cat, old[1], blocks.get(u, 'No_Block')]
    for u, v in data.items():
        if v[0] not in POSITIONED:
            v[1] = 'END'
    for u, v in data.items():
        cat, p, block = v
        if cat in CONSONANTS:
            v[1] = 'BASE_C'
        elif cat in MATRAS:
            if block.startswith('Khmer') or block.startswith('Myanmar'):
                v[0] = 'X'                              # a Khmer / Myanmar vowel category
            else:
                v[1] = matra_position(u, p, block)
        elif cat in SMVD:
            v[1] = 'SMVD'
    for u, p in POSITION_OVERRIDES.items():
        data.setdefault(u, ['X', 'END', None])[1] = p
    out = {}
    for u, (cat, p, _) in data.items():
        if u not in SINGLES and not any(a <= u <= b for a, b in RANGES):
            continue
        c = CATEGORIES.get(cat, 0)
        if (c, POSITIONS[p]) != (0, POSITIONS['END']):
            out[u] = (c, POSITIONS[p])
    return out


def main():
    t = table(sys.argv[1])
    lines = ['"""Indic categories and positions by code point - generated by tools/indic_table.py from',
             'the Unicode 17.0.0 IndicSyllabicCategory, IndicPositionalCategory and Blocks files; do not edit.',
             '',
             'TABLE: {code point: (syllable category, position)}; characters not listed are X / END."""',
             'TABLE = {']
    for u in sorted(t):
        lines.append(f'    0x{u:04X}: {t[u]},')
    lines.append('}')
    open(os.path.join(HERE, 'indic_data.py'), 'w', encoding='utf-8', newline='\n').write('\n'.join(lines) + '\n')
    print(f'{len(t)} characters')
    sys.path.insert(0, HERE)
    import indic                                # the grammar (reads indic_data.py)
    classes, trans, accept = indic.MACHINE
    assert len(trans) < 255
    out = ['; =============================================================================',
           '; Utkarsha OS — lib/ufont/layout/indic_table.asm',
           '; =============================================================================',
           "; The Indic shaper's character table and syllable automaton, generated by",
           '; tools/indic_table.py (Unicode 17.0.0 Indic data, the grammar of',
           '; tools/indic.py); do not edit. See that tool for the layout.',
           '; =============================================================================',
           '',
           'section .rodata',
           'align 4',
           'global indic_chars', 'global indic_chars_count', 'global indic_classes', 'global indic_dfa',
           'global indic_dfa_classes', 'global indic_accept',
           f'indic_chars_count: dd {len(t)}',
           f'indic_dfa_classes: dd {len(trans[0])}',
           'indic_chars:']
    for u in sorted(t):
        out.append(f'    dd 0x{u:04X}')
        out.append(f'    db {t[u][0]}, {t[u][1]}, 0, 0')
    out.append('indic_classes:')
    cls = [classes.get(c, 0) for c in range(64)]
    out += ['    db ' + ', '.join(str(v) for v in cls[i:i + 16]) for i in range(0, 64, 16)]
    out.append('indic_dfa:')
    for row in trans:
        out.append('    db ' + ', '.join(str(v if v >= 0 else 255) for v in row))
    out.append('indic_accept:')
    acc = [a if a >= 0 else 255 for a in accept]
    out += ['    db ' + ', '.join(str(v) for v in acc[i:i + 16]) for i in range(0, len(acc), 16)]
    path = os.path.join(HERE, '..', 'layout', 'indic_table.asm')
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8', newline='\n').write('\n'.join(out) + '\n')
    print(f'{len(trans)} automaton states')


if __name__ == '__main__':
    main()

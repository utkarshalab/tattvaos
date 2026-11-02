#!/usr/bin/env python3
"""Find memory accesses wider than the struc field they name.

Usage: field_width_check.py [root]        (default: the current directory)

An access such as `mov rax, [rbx + S.f]` on a 4-byte field also reads the
next field, and a store overwrites it. The width comes from the register or
size keyword in the instruction; the field is the last S.f in the operand, so
`Surface.current + SurfaceState.x` is judged by SurfaceState.x. A struc field
holding an embedded struc is not a value: naming it alone in a load or store
is reported too. Macro calls are skipped, since their arguments may be loaded
through any register. Exit status 1 if anything is found.

Development-machine tooling only; not part of any OS image.
"""
import os
import re
import sys

RES = {'resb': 1, 'resw': 2, 'resd': 4, 'resq': 8, 'reso': 16, 'resy': 32}
SIZEKW = {'byte': 1, 'word': 2, 'dword': 4, 'qword': 8, 'oword': 16, 'yword': 32}
REG = {}
for form, width in (('r%sx', 8), ('e%sx', 4), ('%sx', 2), ('%sl', 1)):
    for c in 'abcd':
        REG[form % c] = width
for r in ('si', 'di', 'bp', 'sp'):
    REG['r' + r], REG['e' + r], REG[r], REG[r + 'l'] = 8, 4, 2, 1
for i in range(8, 16):
    REG[f'r{i}'], REG[f'r{i}d'], REG[f'r{i}w'], REG[f'r{i}b'] = 8, 4, 2, 1
for i in range(16):
    REG[f'xmm{i}'] = 16
    REG[f'ymm{i}'] = 32

# Fixed-width loads whose register says nothing about the access
NARROW_LOADS = ('movzx', 'movsx', 'movsxd', 'movd', 'movss', 'cvtsi2ss', 'cvtsi2sd')
# Not memory accesses, or block operations
SKIP = ('lea', 'prefetchnta', 'prefetcht0', 'push', 'pop', 'call', 'jmp')

r_struc = re.compile(r'^\s*struc\s+(\w+)')
r_end = re.compile(r'^\s*endstruc')
r_field = re.compile(r'^\s*(?:\.(\w+)\s*:?\s*)?(resb|resw|resd|resq|reso|resy)\s+([^;]+)')
r_token = re.compile(r'\b([A-Z]\w*)\.([a-z]\w*)\b')


def sources(root):
    for top in ('src', 'inc', 'tests'):
        for path, _, names in os.walk(os.path.join(root, top)):
            for name in names:
                if name.endswith(('.asm', '.inc')):
                    yield os.path.join(path, name)


def fields(files):
    """{(struc, field): width}; a field holding a named struc has width None."""
    found = {}
    for path in files:
        current = None
        for line in open(path, encoding='utf-8', errors='replace'):
            code = line.split(';')[0]
            m = r_struc.match(code)
            if m:
                current = m[1]
                continue
            if r_end.match(code):
                current = None
                continue
            m = r_field.match(code) if current else None
            if m and m[1]:
                count = m[3].strip()
                found[(current, m[1])] = (None if re.search(r'[A-Za-z]', count)
                                          else RES[m[2]] * eval(count, {}, {}))
    return found


def access_width(mnemonic, args, operand):
    """Bytes the instruction moves at this operand, or None if unknown."""
    for keyword, width in SIZEKW.items():
        if re.search(r'\b' + keyword + r'\s*\[', operand):
            return width
    for part in re.split(r',(?![^\[]*\])', args):
        part = part.strip().lower()
        if '[' not in part and part in REG:
            return REG[part]
    return None


def scan(path, known, root):
    bad = []
    rel = os.path.relpath(path, root).replace(os.sep, '/')
    for number, line in enumerate(open(path, encoding='utf-8', errors='replace'), 1):
        code = line.split(';')[0]
        m = re.match(r'\s*(?:[.\w]+:)?\s*([A-Za-z_]\w*)\s+(.*)', code)
        if not m or '[' not in m[2]:
            continue
        mnemonic = m[1]
        if mnemonic != mnemonic.lower():
            continue                            # a macro call
        if mnemonic in NARROW_LOADS or mnemonic in SKIP:
            continue
        for operand in re.findall(r'(?:\b\w+\s+)?\[[^\]]*\]', m[2]):
            tokens = [t for t in r_token.finditer(operand) if (t[1], t[2]) in known]
            if not tokens:
                continue
            last = tokens[-1]
            room = known[(last[1], last[2])]
            width = access_width(mnemonic, m[2], operand)
            if room is None:
                bad.append(f'{rel}:{number}: {last[0]} is an embedded struc, not a value')
            elif width is not None and width > room:
                bad.append(f'{rel}:{number}: {last[0]} is {room} bytes, accessed as {width}')
    return bad


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    files = list(sources(root))
    known = fields(files)
    bad = [line for path in files for line in scan(path, known, root)]
    for line in bad:
        print(line)
    print(f'field-width-check: {len(bad)} problems in {len(known)} fields')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()

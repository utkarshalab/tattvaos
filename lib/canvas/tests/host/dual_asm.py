#!/usr/bin/env python3
"""Assemble Canvas with NASM and with utasm and compare the objects (FND-12).

Usage: dual_asm.py <utasm> <nasm flags...> -- <source.asm> ...

Each source is assembled by both (the same -I and -D flags, no debug
information), and the objects compared: every section's bytes, .bss's size,
the relocations (offset, type and what they point at: a local symbol plus
an addend and its section plus an offset are the same place, so both are
compared as section and offset) and the global symbols (name, kind, value).
A source given twice is checked once. lib/umath sources, which ugfx's
umath_unit includes by repository path, are assembled with the repository
root on the include path, as lib/ugfx's Makefile does. A source passes when all of these are the same; it fails
when utasm cannot assemble it or the objects differ, and the first
difference is shown. Exit 1 if any fails, 0 if all pass.

Development-machine tooling only; not part of any OS image.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile


def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def sections(obj, tmp):
    """{name: bytes} of the allocated sections, and .bss's size."""
    out = run(['readelf', '-SW', obj]).stdout
    found = {}
    for m in re.finditer(r'\]\s+(\.\S+)\s+(\w+)\s+[0-9a-f]+\s+[0-9a-f]+\s+([0-9a-f]+)\s+\S+\s+(\S*)', out):
        name, kind, size, flags = m[1], m[2], int(m[3], 16), m[4]
        if 'A' not in flags:
            continue
        if kind == 'NOBITS':
            found[name] = ('size', size)
            continue
        dump = os.path.join(tmp, 'section.bin')
        run(['objcopy', '-O', 'binary', f'--only-section={name}', obj, dump])
        found[name] = ('bytes', open(dump, 'rb').read() if os.path.exists(dump) else b'')
        if os.path.exists(dump):
            os.remove(dump)
    return found


def local_places(obj):
    """{symbol: (section, value)} for every symbol defined in obj."""
    out = run(['readelf', '-sW', obj]).stdout
    shdr = run(['readelf', '-SW', obj]).stdout
    names = {int(m[1]): m[2] for m in re.finditer(r'\[\s*(\d+)\]\s+(\S+)', shdr)}
    places = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 8 and parts[6].isdigit():
            section = names.get(int(parts[6]), parts[6])
            places[parts[7]] = (section, int(parts[1], 16))
    return places


def relocations(obj):
    """[(section, offset, type, target)]; target a (section, offset) where
    the symbol is defined here, else (symbol, addend)."""
    out = run(['readelf', '-rW', obj]).stdout
    places = local_places(obj)
    rels, section = [], None
    for line in out.splitlines():
        m = re.match(r"Relocation section '(\S+)'", line)
        if m:
            section = m[1]
            continue
        m = re.match(r'\s*([0-9a-f]+)\s+[0-9a-f]+\s+(R_\S+)\s+[0-9a-f]+\s+(\S+)\s*([+-])\s*([0-9a-f]+)', line)
        if not m or not section or 'debug' in section:
            continue
        name = m[3]
        addend = int(m[5], 16) * (1 if m[4] == '+' else -1)
        if name in places:
            target_section, value = places[name]
            target = (target_section, value + addend)
        else:
            target = (name, addend)
        rels.append((section, int(m[1], 16), m[2], target))
    return sorted(rels)


def symbols(obj):
    out = run(['nm', '-P', '--defined-only', obj]).stdout
    syms = set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and not parts[0].startswith('..@') and parts[1] not in 'Nn':
            if parts[1].isupper():             # globals: name, kind, value
                syms.add((parts[0], parts[1], parts[2]))
    return syms


def compare(a, b, tmp):
    sa, sb = sections(a, tmp), sections(b, tmp)
    for name in sorted(set(sa) | set(sb)):
        if sa.get(name) != sb.get(name):
            x, y = sa.get(name), sb.get(name)
            if x is None or y is None:
                return f'section {name} only in {"NASM" if y is None else "utasm"}\'s'
            if x[0] == 'size' or y[0] == 'size':
                return f'{name}: size {x[1]} != {y[1]}'
            bx, by = x[1], y[1]
            if len(bx) != len(by):
                return f'{name}: {len(bx)} bytes != {len(by)}'
            i = next(k for k in range(len(bx)) if bx[k] != by[k])
            return f'{name}: first difference at 0x{i:x}'
    ra, rb = relocations(a), relocations(b)
    if ra != rb:
        diff = sorted(set(ra) ^ set(rb))
        return f'relocations differ ({len(diff)}), first {diff[0]}'
    ya, yb = symbols(a), symbols(b)
    if ya != yb:
        diff = sorted(ya ^ yb)
        return f'globals differ ({len(diff)}), first {diff[0]}'
    return None


def main():
    if '--' not in sys.argv or len(sys.argv) < 4:
        print(__doc__)
        return 1
    i = sys.argv.index('--')
    utasm, flags, sources = sys.argv[1], sys.argv[2:i], sys.argv[i + 1:]
    sources = list(dict.fromkeys(sources))
    flags = [f for f in flags if f not in ('-g', '-F', 'dwarf') and f != '-Werror']
    tmp = tempfile.mkdtemp(prefix='canvas_dual_asm_')
    passed, failed = 0, []
    try:
        for src in sources:
            a, b = os.path.join(tmp, 'nasm.o'), os.path.join(tmp, 'utasm.o')
            extra = ['-I', '../../'] if src.endswith('umath_unit.asm') else []
            r = run(['nasm'] + flags + extra + ['-o', a, src])
            if r.returncode:
                failed.append((src, 'NASM: ' + (r.stderr.strip().splitlines() or ['?'])[0]))
                continue
            r = run([utasm] + flags + extra + ['-o', b, src])
            if r.returncode or not os.path.exists(b):
                msg = (r.stderr.strip() or r.stdout.strip()).splitlines()
                failed.append((src, 'utasm: ' + (msg[0] if msg else f'exit {r.returncode}')))
                continue
            why = compare(a, b, tmp)
            if why:
                failed.append((src, why))
            else:
                passed += 1
            os.remove(a)
            os.remove(b)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for src, why in failed:
        print(f'dual-asm: FAIL {src}: {why}')
    print(f'dual-asm: {passed}/{len(sources)} identical, {len(failed)} differ or fail')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

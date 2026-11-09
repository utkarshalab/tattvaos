#!/usr/bin/env python3
"""Check that Canvas's symbols are consistent (FND-03).

Usage: symbol_check.py <object> ...  (the objects canvasd links)

For the objects given:
  1. no global is defined by two of them;
  2. every symbol one uses is defined by one of them;
  3. in every .asm source the objects came from (canvas's own, under src/),
     each `extern` names something the file uses, and each `global` names a
     label the file defines.
Exit 1, with each problem listed, if any rule is broken.

Development-machine tooling only; not part of any OS image.
"""
import os
import re
import subprocess
import sys


def symbols(obj):
    """(defined globals, undefined) of one object, from nm."""
    out = subprocess.run(['nm', '-P', obj], capture_output=True, text=True,
                         check=True).stdout
    defined, undefined = set(), set()
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 2:
            continue
        name, kind = parts[0], parts[1]
        if kind == 'U':
            undefined.add(name)
        elif kind.isupper():                    # a global definition
            defined.add(name)
    return defined, undefined


def source_of(obj):
    """build/obj/x/y.o (or build/release/obj/...) -> src/x/y.asm, if there."""
    m = re.search(r'/obj/(.*)\.o$', obj.replace('\\', '/'))
    if not m:
        return None
    src = os.path.join('src', m.group(1) + '.asm')
    return src if os.path.exists(src) else None


def code_lines(path):
    """The file's lines without comments or string literals."""
    out = []
    for line in open(path, encoding='utf-8', errors='replace'):
        line = re.sub(r'"[^"]*"|\'[^\']*\'|`[^`]*`', '""', line)
        out.append(line.split(';', 1)[0])
    return out


def check_source(path):
    problems = []
    lines = code_lines(path)
    text = '\n'.join(lines)
    words = re.findall(r'[A-Za-z_.$?@][\w.$?@]*', text)
    count = {}
    for w in words:
        count[w] = count.get(w, 0) + 1
    labels = set(re.findall(r'^\s*([A-Za-z_][\w.$?@]*)\s*:', text, re.M))
    labels |= set(re.findall(r'^\s*([A-Za-z_][\w.$?@]*)\s+(?:equ|d[bwdqt]|res[bwdqt]|times)\b',
                             text, re.M | re.I))
    for line in lines:
        m = re.match(r'\s*extern\s+(.*)', line)
        if m:
            for name in [n.strip() for n in m.group(1).split(',') if n.strip()]:
                if count.get(name, 0) < 2:      # the extern line itself only
                    problems.append(f'{path}: extern {name} is not used')
        m = re.match(r'\s*global\s+(.*)', line)
        if m:
            for name in [n.strip().split(':')[0] for n in m.group(1).split(',') if n.strip()]:
                if name.startswith('%'):        # inside a macro: its argument
                    continue
                if name not in labels and count.get(name, 0) < 2:
                    problems.append(f'{path}: global {name} is not defined here')
    return problems


def main():
    objs = sys.argv[1:]
    if not objs:
        print(__doc__)
        return 1
    problems = []
    where = {}
    used = {}
    for obj in objs:
        defined, undefined = symbols(obj)
        for name in defined:
            where.setdefault(name, []).append(obj)
        for name in undefined:
            used.setdefault(name, []).append(obj)
    for name, objs_of in sorted(where.items()):
        if len(objs_of) > 1:
            problems.append(f'{name} is defined by {len(objs_of)} objects: '
                            + ', '.join(objs_of))
    for name, objs_of in sorted(used.items()):
        if name not in where:
            problems.append(f'{name} is used by {objs_of[0]}'
                            + (f' and {len(objs_of) - 1} more' if len(objs_of) > 1 else '')
                            + ' and defined by none')
    for obj in objs:
        src = source_of(obj)
        if src:
            problems += check_source(src)
    for p in problems:
        print('symbol-check:', p)
    print(f'symbol-check: {len(objs)} objects, {len(where)} globals, '
          f'{len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())

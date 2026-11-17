#!/usr/bin/env python3
"""Every request handler reads only the payload bytes it was promised.

Usage: payload_check.py [root]        (default: the current directory)

A handler opens with `HANDLER name, least`: the server refuses a message
whose payload is shorter than `least` bytes before the handler runs. The
payload sits in one buffer the server reuses for every message, so a read
past the message's own bytes sees what an earlier message left there,
perhaps another client's. This check reads every HANDLER ... HANDLER_END
block of src/server/server_core.asm and reports:

  * a read through r13 (the payload) whose offset plus width is more than
    `least`: `mov eax, [r13 + 8]` needs at least 12;
  * a read through r13 at an offset it cannot work out, or with a register
    index;
  * the payload passed on (`mov rdx, r13`, `lea rsi, [r13 + 4]`) without a
    `; payload N` note on that line (N an expression, then optionally a
    colon and words) saying how many bytes from there the callee reads, N
    within `least`; the handler may instead check the
    length itself (it reads `MsgHdr.len`), or pass the payload only as the
    buffer of a reply (a `call reply` within the next three lines).

Writes into the payload are not reads: handlers build replies there. The
width comes from the size keyword or the register. Exit status 1 if anything
is found.

Development-machine tooling only; not part of any OS image.
"""
import os
import re
import sys

SIZEKW = {'byte': 1, 'word': 2, 'dword': 4, 'qword': 8, 'oword': 16, 'yword': 32}
REG = {}
for form, width in (('r%sx', 8), ('e%sx', 4), ('%sx', 2), ('%sl', 1)):
    for c in 'abcd':
        REG[form % c] = width
for r in ('si', 'di', 'bp', 'sp'):
    REG['r' + r], REG['e' + r], REG[r], REG[r + 'l'] = 8, 4, 2, 1
for i in range(8, 16):
    REG[f'r{i}'], REG[f'r{i}d'], REG[f'r{i}w'], REG[f'r{i}b'] = 8, 4, 2, 1
for i in range(32):
    REG[f'xmm{i}'], REG[f'ymm{i}'], REG[f'zmm{i}'] = 16, 32, 64
# instructions whose first operand is only written
STORES = {'mov', 'movdqu', 'movdqa', 'movups', 'movaps', 'movq', 'movd',
          'movnti', 'movntdq', 'vmovdqu', 'vmovdqa'}
# instructions whose memory operand is read at a width other than the
# register's
WIDEN = {'movzx', 'movsx', 'movsxd'}


def defines(root):
    """%define NAME number|expression from inc/ and the handlers' file."""
    out = {}
    files = [os.path.join(root, 'inc', f) for f in os.listdir(os.path.join(root, 'inc'))
             if f.endswith('.inc')]
    files.append(os.path.join(root, 'src', 'server', 'server_core.asm'))
    for path in files:
        with open(path, encoding='utf-8', errors='replace') as f:
            for line in f:
                m = re.match(r'\s*%define\s+(\w+)\s+([^;]+)', line)
                if m:
                    out[m.group(1)] = m.group(2).strip()
    return out


def value(expr, defs, depth=0):
    """The number an expression of numbers, names and + - * << stands for."""
    if depth > 8:
        return None
    def name(m):
        v = defs.get(m.group(0))
        if v is None:
            raise KeyError(m.group(0))
        r = value(v, defs, depth + 1)
        if r is None:
            raise KeyError(m.group(0))
        return str(r)
    try:
        text = re.sub(r'\b[A-Za-z_]\w*\b', name, expr)
    except KeyError:
        return None
    if not re.fullmatch(r'[\d\sxXa-fA-F+\-*()<>]*', text):
        return None
    try:
        return int(eval(text, {'__builtins__': {}}))
    except Exception:
        return None


def operands(text):
    """The comma-separated operands of an instruction, brackets kept whole."""
    out, depth, cur = [], 0, ''
    for ch in text:
        if ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
        if ch == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def check(root):
    defs = defines(root)
    path = os.path.join(root, 'src', 'server', 'server_core.asm')
    with open(path, encoding='utf-8') as f:
        lines = f.read().split('\n')
    problems = []
    i = 0
    while i < len(lines):
        m = re.match(r'HANDLER\s+(\w+)\s*,\s*([^;]+)', lines[i])
        if not m:
            i += 1
            continue
        name, least_text = m.group(1), m.group(2).strip()
        least = value(least_text, defs)
        start = i + 1
        i += 1
        while i < len(lines) and not lines[i].startswith('HANDLER_END'):
            i += 1
        body = lines[start:i]
        where = lambda k: f'{path}:{start + k + 1}: {name}'
        if least is None:
            problems.append(f'{where(-1)}: cannot work out {least_text!r}')
            continue
        checks_len = any('MsgHdr.len' in l for l in body)
        for k, raw in enumerate(body):
            code, _, comment = raw.partition(';')
            code = code.strip()
            if not code or code.startswith('%') or code.endswith(':'):
                continue
            parts = code.split(None, 1)
            op = parts[0].lower()
            ops = operands(parts[1]) if len(parts) > 1 else []
            # the payload passed on
            passed = None
            if op == 'mov' and len(ops) == 2 and ops[1] == 'r13' and ops[0] != 'r13':
                passed = 0
            elif op == 'lea' and len(ops) == 2 and re.search(r'\[\s*r13\b', ops[1]):
                inner = ops[1].strip('[]')
                off = inner[len('r13'):].strip()
                passed = 0 if not off else value(off.lstrip('+').strip(), defs) if off.startswith('+') else None
                if passed is None:
                    problems.append(f'{where(k)}: payload address at an unknown offset: {code}')
                    continue
            if passed is not None:
                note = re.search(r'payload\s+([^:]+)', comment)
                if note:
                    n = value(note.group(1), defs)
                    if n is None:
                        problems.append(f'{where(k)}: cannot work out the note {note.group(1)!r}')
                    elif passed + n > least:
                        problems.append(f'{where(k)}: the callee reads {passed}+{n} bytes, '
                                        f'the handler promises {least}')
                    continue
                if checks_len:
                    continue
                follow = body[k + 1:k + 4]
                if any(re.match(r'\s*call\s+reply\b', l) for l in follow):
                    continue
                problems.append(f'{where(k)}: payload passed on with no `; payload N` note: {code}')
                continue
            # reads through r13
            for n_op, operand in enumerate(ops):
                mem = re.search(r'\[\s*r13\b([^\]]*)\]', operand)
                if not mem:
                    continue
                if n_op == 0 and op in STORES:
                    continue                    # a write: a reply being built
                rest = mem.group(1).strip()
                if rest and not rest.startswith('+'):
                    problems.append(f'{where(k)}: payload read at an unknown offset: {code}')
                    continue
                off = 0 if not rest else value(rest[1:].strip(), defs)
                if off is None:
                    problems.append(f'{where(k)}: payload read at an unknown offset: {code}')
                    continue
                width = None
                kw = re.match(r'(\w+)\s*\[', operand)
                if kw and kw.group(1).lower() in SIZEKW:
                    width = SIZEKW[kw.group(1).lower()]
                elif op not in WIDEN:
                    other = [o for j, o in enumerate(ops) if j != n_op]
                    for o in other:
                        if o.lower() in REG:
                            width = REG[o.lower()]
                            break
                if width is None:
                    problems.append(f'{where(k)}: cannot tell how wide this read is: {code}')
                    continue
                if off + width > least:
                    problems.append(f'{where(k)}: reads bytes {off}..{off + width - 1}, '
                                    f'the handler promises {least}: {code}')
    return problems


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else '.'
    problems = check(root)
    for p in problems:
        print(p)
    if problems:
        print(f'payload-check: {len(problems)} found')
        return 1
    print('payload-check: every handler reads only the payload it was promised')
    return 0


if __name__ == '__main__':
    sys.exit(main())

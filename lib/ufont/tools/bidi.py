"""The Unicode Bidirectional Algorithm (UAX #9, Unicode 17) - the model lib/ufont's
layout/bidi.asm follows, checked against Unicode's BidiTest.txt and BidiCharacterTest.txt
(tests/host/bidi_check.py).

    levels, para = resolve(classes, direction, brackets)
    order = reorder(levels)

classes: one Bidi_Class name per character ('L', 'R', 'AL', 'EN', ...); direction: 0 left to right,
1 right to left, 2 from the text (P2, P3); brackets: per character (pair id, 'o' / 'c') or None
(BD14 - BD16; pair id: the opening bracket's code point, canonical equivalents folded). levels: per
character its level, None for those X9 removes; reorder: the indices left to right, removed
characters left out (L2 over one line).

Development-machine tooling only; not part of any OS image.
"""
import os

MAX_DEPTH = 125
ISOLATES = ('LRI', 'RLI', 'FSI')
REMOVED = ('RLE', 'LRE', 'RLO', 'LRO', 'PDF', 'BN')
NI = ('B', 'S', 'WS', 'ON', 'LRI', 'RLI', 'FSI', 'PDI')


def _matching_pdi(classes, i):
    """The index of the PDI matching the isolate initiator at i, or len(classes)."""
    depth = 1
    for j in range(i + 1, len(classes)):
        t = classes[j]
        if t in ISOLATES:
            depth += 1
        elif t == 'PDI':
            depth -= 1
            if depth == 0:
                return j
        elif t == 'B':
            break
    return len(classes)


def first_strong(classes, start, end):
    """P2: 0 for L, 1 for R / AL, None - isolates skipped, stopping at a paragraph separator."""
    i = start
    while i < end:
        t = classes[i]
        if t == 'L':
            return 0
        if t in ('R', 'AL'):
            return 1
        if t in ISOLATES:
            i = _matching_pdi(classes, i)
        elif t == 'B':
            break
        i += 1
    return None


def resolve(classes, direction=2, brackets=None):
    n = len(classes)
    orig = list(classes)
    t = list(classes)
    if brackets is None:
        brackets = [None] * n
    if direction == 2:
        para = first_strong(t, 0, n) or 0
    else:
        para = direction
    levels = [para] * n
    # X1 - X8: explicit levels and directions
    stack = [(para, None, False)]          # level, override ('L' / 'R' / None), isolate
    over_iso = over_emb = valid_iso = 0
    match_pdi = {}
    for i in range(n):
        c = t[i]
        level, override, _ = stack[-1]
        if c in ('RLE', 'LRE', 'RLO', 'LRO'):
            rtl = c in ('RLE', 'RLO')
            new = (level + 1) | 1 if rtl else (level + 2) & ~1
            if new <= MAX_DEPTH and not over_iso and not over_emb:
                ov = None if c in ('RLE', 'LRE') else ('R' if rtl else 'L')
                stack.append((new, ov, False))
            elif not over_iso:
                over_emb += 1
            levels[i] = level
        elif c in ISOLATES:
            levels[i] = level
            if override:
                t[i] = override
            if c == 'FSI':
                end = _matching_pdi(orig, i)
                rtl = first_strong(orig, i + 1, end) == 1
            else:
                rtl = c == 'RLI'
            new = (level + 1) | 1 if rtl else (level + 2) & ~1
            if new <= MAX_DEPTH and not over_iso and not over_emb:
                valid_iso += 1
                stack.append((new, None, True))
            else:
                over_iso += 1
        elif c == 'PDI':
            if over_iso:
                over_iso -= 1
            elif valid_iso:
                over_emb = 0
                while not stack[-1][2]:
                    stack.pop()
                stack.pop()
                valid_iso -= 1
            level, override, _ = stack[-1]
            levels[i] = level
            if override:
                t[i] = override
        elif c == 'PDF':
            if over_iso:
                pass
            elif over_emb:
                over_emb -= 1
            elif not stack[-1][2] and len(stack) >= 2:
                stack.pop()
            levels[i] = level
        elif c == 'B':
            levels[i] = para
        elif c == 'BN':
            levels[i] = level
        else:
            levels[i] = level
            if override:
                t[i] = override
    # X9: removed characters; X10: level runs joined through isolates into sequences
    kept = [i for i in range(n) if orig[i] not in REMOVED]
    runs = []
    for i in kept:
        if runs and levels[runs[-1][-1]] == levels[i]:
            runs[-1].append(i)
        else:
            runs.append([i])
    # match isolate initiators to PDIs among the kept characters
    stack_i = []
    for i in kept:
        if orig[i] in ISOLATES:
            stack_i.append(i)
        elif orig[i] == 'PDI' and stack_i:
            match_pdi[stack_i.pop()] = i
        elif orig[i] == 'B':
            stack_i = []
    matched = set(match_pdi.values())
    run_of = {}
    for k, r in enumerate(runs):
        run_of[r[0]] = k
    seqs = []
    used = set()
    for k, r in enumerate(runs):
        if k in used:
            continue
        if orig[r[0]] == 'PDI' and r[0] in matched:
            continue                                 # continues a sequence started earlier
        seq = list(r)
        used.add(k)
        while orig[seq[-1]] in ISOLATES and match_pdi.get(seq[-1]) in run_of:
            k2 = run_of[match_pdi[seq[-1]]]
            used.add(k2)
            seq += runs[k2]
        seqs.append(seq)
    pos = {i: p for p, i in enumerate(kept)}
    for seq in seqs:
        lv = levels[seq[0]]
        p0 = pos[seq[0]]
        prev = levels[kept[p0 - 1]] if p0 > 0 else para
        p1 = pos[seq[-1]]
        if orig[seq[-1]] in ISOLATES or p1 + 1 >= len(kept):
            nxt = para
        else:
            nxt = levels[kept[p1 + 1]]
        sos = 'R' if max(lv, prev) & 1 else 'L'
        eos = 'R' if max(lv, nxt) & 1 else 'L'
        _resolve_sequence(seq, t, orig, lv, sos, eos, brackets)
    # I1, I2
    for i in kept:
        c = t[i]
        if levels[i] & 1:
            if c in ('L', 'EN', 'AN'):
                levels[i] += 1
        elif c == 'R':
            levels[i] += 1
        elif c in ('AN', 'EN'):
            levels[i] += 2
    # L1: separators, and white space and isolates before them or the end, at the paragraph level
    trailing = True
    for i in range(n - 1, -1, -1):
        c = orig[i]
        if c in ('S', 'B'):
            levels[i] = para
            trailing = True
        elif c in ('WS', 'FSI', 'LRI', 'RLI', 'PDI') or c in REMOVED:
            if trailing:
                levels[i] = para
        else:
            trailing = False
    out = [None if orig[i] in REMOVED else levels[i] for i in range(n)]
    return out, para


def _resolve_sequence(seq, t, orig, level, sos, eos, brackets):
    n = len(seq)
    ty = [t[i] for i in seq]
    # W1: NSM takes the type before it (ON after an isolate initiator or PDI; sos at the start)
    for k in range(n):
        if ty[k] == 'NSM':
            if k == 0:
                ty[k] = sos
            elif ty[k - 1] in ISOLATES or ty[k - 1] == 'PDI':
                ty[k] = 'ON'
            else:
                ty[k] = ty[k - 1]
    # W2: EN after AL -> AN; W3: AL -> R
    last = sos
    for k in range(n):
        c = ty[k]
        if c in ('L', 'R', 'AL'):
            last = c
        elif c == 'EN' and last == 'AL':
            ty[k] = 'AN'
    for k in range(n):
        if ty[k] == 'AL':
            ty[k] = 'R'
    # W4: a single separator between numbers
    for k in range(1, n - 1):
        if ty[k] == 'ES' and ty[k - 1] == 'EN' and ty[k + 1] == 'EN':
            ty[k] = 'EN'
        elif ty[k] == 'CS' and ty[k - 1] == ty[k + 1] and ty[k - 1] in ('EN', 'AN'):
            ty[k] = ty[k - 1]
    # W5: terminators next to European numbers
    k = 0
    while k < n:
        if ty[k] == 'ET':
            e = k
            while e < n and ty[e] == 'ET':
                e += 1
            if (k > 0 and ty[k - 1] == 'EN') or (e < n and ty[e] == 'EN'):
                for j in range(k, e):
                    ty[j] = 'EN'
            k = e
        else:
            k += 1
    # W6: the other separators and terminators -> ON
    for k in range(n):
        if ty[k] in ('ES', 'ET', 'CS'):
            ty[k] = 'ON'
    # W7: EN after L (or sos L) -> L
    last = sos
    for k in range(n):
        c = ty[k]
        if c in ('L', 'R'):
            last = c
        elif c == 'EN' and last == 'L':
            ty[k] = 'L'
    # N0: bracket pairs
    e = 'R' if level & 1 else 'L'
    pairs = []
    stack = []
    for k in range(n):
        b = brackets[seq[k]]
        if b is None or ty[k] != 'ON':
            continue
        pid, kind = b
        if kind == 'o':
            if len(stack) == 63:
                break
            stack.append((pid, k))
        else:
            for s in range(len(stack) - 1, -1, -1):
                if stack[s][0] == pid:
                    pairs.append((stack[s][1], k))
                    del stack[s:]
                    break
    pairs.sort()

    def strong(c):
        return 'L' if c == 'L' else 'R' if c in ('R', 'EN', 'AN') else None

    for o, c in pairs:
        found = None
        for k in range(o + 1, c):
            s = strong(ty[k])
            if s == e:
                found = e
                break
            if s:
                found = s
        if found is None:
            continue
        if found != e:
            before = sos
            for k in range(o - 1, -1, -1):
                s = strong(ty[k])
                if s:
                    before = s
                    break
            found = before if before != e else e
        ty[o] = ty[c] = found
        for b in (o, c):
            k = b + 1
            while k < n and orig[seq[k]] == 'NSM':
                ty[k] = found
                k += 1
    # N1, N2: neutrals between strong types take theirs, else the embedding direction
    k = 0
    while k < n:
        if ty[k] in NI:
            s = k
            while k < n and ty[k] in NI:
                k += 1
            before = sos if s == 0 else strong(ty[s - 1])
            after = eos if k == n else strong(ty[k])
            d = before if before == after else e
            for j in range(s, k):
                ty[j] = d
        else:
            k += 1
    for k in range(n):
        t[seq[k]] = ty[k]


def reorder(levels):
    """L2: the indices (removed characters left out) in visual order."""
    idx = [i for i, lv in enumerate(levels) if lv is not None]
    if not idx:
        return []
    lv = [levels[i] for i in idx]
    hi = max(lv)
    lo = min(x for x in lv if x & 1) if any(x & 1 for x in lv) else hi + 1
    for level in range(hi, lo - 1, -1):
        k = 0
        while k < len(idx):
            if lv[k] >= level:
                s = k
                while k < len(idx) and lv[k] >= level:
                    k += 1
                idx[s:k] = idx[s:k][::-1]
                lv[s:k] = lv[s:k][::-1]
            else:
                k += 1
    return idx


# ---------------------------------------------------------------- character data
def load(ucd):
    """-> (bidi class of a code point, bracket of a code point) from the UCD directory."""
    cls = {}
    ranges = []
    for line in open(os.path.join(ucd, 'DerivedBidiClass.txt'), encoding='utf-8'):
        if line.startswith('# @missing:'):
            r, v = line[11:].split(';')
            a, b = r.strip().split('..')
            ranges.append((int(a, 16), int(b, 16), _alias(v.strip())))
            continue
        line = line.split('#')[0].strip()
        if not line:
            continue
        r, v = [x.strip() for x in line.split(';')]
        a, b = (r.split('..') + [r])[:2]
        for u in range(int(a, 16), int(b, 16) + 1):
            cls[u] = v
    br = {}
    for line in open(os.path.join(ucd, 'BidiBrackets.txt'), encoding='utf-8'):
        line = line.split('#')[0].strip()
        if not line:
            continue
        u, p, k = [x.strip() for x in line.split(';')]
        u, p = int(u, 16), int(p, 16)
        pid = u if k == 'o' else p
        br[u] = (0x3008 if pid == 0x2329 else pid, k)            # canonical equivalents: one pair

    def bidi_class(u):
        c = cls.get(u)
        if c is not None:
            return c
        for a, b, v in reversed(ranges):
            if a <= u <= b:
                return v
        return 'L'

    return bidi_class, br.get


def from_data():
    """-> (bidi class, bracket) from ucd_data.py (generated) - no UCD directory needed."""
    import bisect
    import ucd_data
    starts = [r[0] for r in ucd_data.BIDI_RANGES]

    def bidi_class(u):
        return ucd_data.BIDI_RANGES[bisect.bisect_right(starts, u) - 1][1]

    return bidi_class, ucd_data.BRACKETS.get


_ALIASES = {'Left_To_Right': 'L', 'Right_To_Left': 'R', 'Arabic_Letter': 'AL', 'European_Terminator': 'ET',
            'Boundary_Neutral': 'BN', 'Other_Neutral': 'ON', 'Nonspacing_Mark': 'NSM'}


def _alias(v):
    return _ALIASES.get(v, v)

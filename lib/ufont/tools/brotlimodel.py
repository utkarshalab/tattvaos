"""Brotli decompression (RFC 7932) - the model sfnt/brotli.asm follows, checked against the brotli
module (tests/host/brotli_check.py).

    decompress(data, limit) -> bytes, or None for a damaged stream or one longer than limit

Window size from the stream header; meta-blocks: last / empty, metadata skipped, uncompressed,
compressed - block types and counts for the three categories, distance parameters, literal
context modes, context maps (run-length zeros, inverse move-to-front), prefix codes (simple and
complex, the code length code), then commands: insert-and-copy codes, literals by context,
distances (the last-four ring, short codes, direct and postfix codes) and references into the
static dictionary through its 121 transforms.

Development-machine tooling only; not part of any OS image.
"""
import os

import brotli_data as T

HERE = os.path.dirname(os.path.abspath(__file__))
_DICT = None

CL_ORDER = [1, 2, 3, 4, 0, 5, 17, 6, 16, 7, 8, 9, 10, 11, 12, 13, 14, 15]
BLOCK_OFF = [1, 5, 9, 13, 17, 25, 33, 41, 49, 65, 81, 97, 113, 145, 177, 209, 241, 305, 369, 497, 753, 1265,
             2289, 4337, 8433, 16625]
BLOCK_BITS = [2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 6, 6, 7, 8, 9, 10, 11, 12, 13, 24]
INS_BITS = [0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 12, 14, 24]
INS_OFF = [0, 1, 2, 3, 4, 5, 6, 8, 10, 14, 18, 26, 34, 50, 66, 98, 130, 194, 322, 578, 1090, 2114, 6210, 22594]
COPY_BITS = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 24]
COPY_OFF = [2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 18, 22, 30, 38, 54, 70, 102, 134, 198, 326, 582, 1094, 2118]
# per 64-code cell: (insert code base, copy code base)
CELLS = [(0, 0), (0, 8), (0, 0), (0, 8), (8, 0), (8, 8), (0, 16), (16, 0), (8, 16), (16, 8), (16, 16)]
# short distance codes 0..15: (which of the last four, delta)
SHORT = [(0, 0), (1, 0), (2, 0), (3, 0), (0, -1), (0, 1), (0, -2), (0, 2), (0, -3), (0, 3), (1, -1), (1, 1),
         (1, -2), (1, 2), (1, -3), (1, 3)]


def dictionary():
    global _DICT
    if _DICT is None:
        _DICT = open(os.path.join(HERE, '..', 'include', 'brotli_dict.dat'), 'rb').read()
    return _DICT


class Bad(Exception):
    pass


class Bits:
    def __init__(self, data):
        self.data, self.pos, self.bit = data, 0, 0

    def read(self, n):
        v = 0
        for k in range(n):
            if self.pos >= len(self.data):
                raise Bad
            v |= ((self.data[self.pos] >> self.bit) & 1) << k
            self.bit += 1
            if self.bit == 8:
                self.bit, self.pos = 0, self.pos + 1
        return v

    def align(self):
        if self.bit:
            if self.data[self.pos] >> self.bit:                 # the padding must be zero
                raise Bad
            self.bit, self.pos = 0, self.pos + 1


class Code:
    """A canonical prefix code (DEFLATE's convention: codes from the first bit read)."""

    def __init__(self, lengths):
        self.count = [0] * 16
        for n in lengths:
            self.count[n] += 1
        self.single = None
        nz = [s for s, n in enumerate(lengths) if n]
        self.symbols = sorted(nz, key=lambda s: (lengths[s], s))
        self.count[0] = 0

    def read(self, b):
        if self.single is not None:
            return self.single
        code = first = index = 0
        for n in range(1, 16):
            code |= b.read(1)
            c = self.count[n]
            if code - c < first:
                return self.symbols[index + (code - first)]
            index += c
            first = (first + c) << 1
            code <<= 1
        raise Bad


def read_code(b, size):
    """A prefix code over an alphabet of size symbols."""
    hskip = b.read(2)
    if hskip == 1:
        nbits = max(1, (size - 1).bit_length())
        nsym = b.read(2) + 1
        syms = [b.read(nbits) for _ in range(nsym)]
        if any(s >= size for s in syms) or len(set(syms)) != nsym:
            raise Bad
        if nsym == 1:
            c = Code([0] * size)
            c.single = syms[0]
            return c
        lens = {2: [1, 1], 3: [1, 2, 2], 4: [2, 2, 2, 2]}[nsym]
        if nsym == 4 and b.read(1):
            lens = [1, 2, 3, 3]
        lengths = [0] * size
        for s, n in zip(syms, lens):
            lengths[s] = n
        return Code(lengths)
    # the code length code
    cl = [0] * 18
    space, num = 32, 0
    for i in range(hskip, 18):
        # the code length code (bits as read): 00 0, 10 3, 01 4, 011 2, 0111 1, 1111 5
        if not b.read(1):
            v = 3 if b.read(1) else 0
        elif not b.read(1):
            v = 4
        elif not b.read(1):
            v = 2
        else:
            v = 5 if b.read(1) else 1
        cl[CL_ORDER[i]] = v
        if v:
            space -= 32 >> v
            num += 1
            if space <= 0:
                break
    if not (num == 1 or space == 0):
        raise Bad
    clc = Code(cl)
    if num == 1:
        clc.single = next(s for s, n in enumerate(cl) if n)
    # the symbols' code lengths
    lengths = [0] * size
    sym, prev, repeat, rlen = 0, 8, 0, 0
    space = 32768
    while sym < size and space > 0:
        c = clc.read(b)
        if c < 16:
            repeat = 0
            lengths[sym] = c
            if c:
                prev = c
                space -= 32768 >> c
            sym += 1
        else:
            extra = 2 if c == 16 else 3
            new = prev if c == 16 else 0
            if rlen != new:
                repeat, rlen = 0, new
            old = repeat
            if repeat > 0:
                repeat = (repeat - 2) << extra
            repeat += b.read(extra) + 3
            delta = repeat - old
            if sym + delta > size:
                raise Bad
            for _ in range(delta):
                lengths[sym] = rlen
                sym += 1
            if rlen:
                space -= delta << (15 - rlen)
    if space != 0:
        raise Bad
    return Code(lengths)


def read_count(b):
    """NBLTYPES / NTREES: 1..256."""
    if not b.read(1):
        return 1
    n = b.read(3)
    return (1 << n) + b.read(n) + 1


def read_block_count(b, code):
    s = code.read(b)
    return BLOCK_OFF[s] + b.read(BLOCK_BITS[s])


def read_context_map(b, size, ntrees):
    if ntrees < 2:
        return [0] * size
    rlemax = b.read(4) + 1 if b.read(1) else 0
    code = read_code(b, ntrees + rlemax)
    out = []
    while len(out) < size:
        s = code.read(b)
        if s == 0:
            out.append(0)
        elif s <= rlemax:
            reps = (1 << s) + b.read(s)
            if len(out) + reps > size:
                raise Bad
            out += [0] * reps
        else:
            out.append(s - rlemax)
    if b.read(1):                                               # inverse move-to-front
        mtf = list(range(256))
        for i, v in enumerate(out):
            x = mtf[v]
            out[i] = x
            if v:
                del mtf[v]
                mtf.insert(0, x)
    return out


class Category:
    def __init__(self, b):
        self.n = read_count(b)
        self.type, self.prev, self.count = 0, 1, 1 << 24
        if self.n >= 2:
            self.tcode = read_code(b, self.n + 2)
            self.ccode = read_code(b, 26)
            self.count = read_block_count(b, self.ccode)

    def next(self, b):
        """A block switch when the count is out; one taken."""
        if self.count == 0:
            s = self.tcode.read(b)
            t = self.prev if s == 0 else (self.type + 1) % self.n if s == 1 else s - 2
            if t >= self.n:
                raise Bad
            self.prev, self.type = self.type, t
            self.count = read_block_count(b, self.ccode)
        self.count -= 1


def transform(word, t):
    pre, kind, suf = T.TRANSFORMS[t]
    w = bytearray(word)
    if 3 <= kind <= 11:
        w = w[kind - 2:]
    elif 12 <= kind <= 20:
        w = w[:max(0, len(w) - (kind - 11))]
    elif kind in (1, 2):
        i = 0
        while i < len(w):
            c = w[i]
            if c < 192:
                if 97 <= c <= 122:
                    w[i] ^= 32
                step = 1
            elif c < 224:
                if i + 1 < len(w):
                    w[i + 1] ^= 32
                step = 2
            else:
                if i + 2 < len(w):
                    w[i + 2] ^= 5
                step = 3
            if kind == 1:
                break
            i += step
    return pre + bytes(w) + suf


def decompress(data, limit=1 << 28):
    try:
        return _decompress(data, limit)
    except (Bad, IndexError):
        return None


def _decompress(data, limit):
    b = Bits(data)
    # WBITS
    if not b.read(1):
        wbits = 16
    else:
        n = b.read(3)
        if n:
            wbits = 17 + n
        else:
            m = b.read(3)
            if m == 1:
                raise Bad
            wbits = 8 + m if m else 17
    maxback = (1 << wbits) - 16
    out = bytearray()
    dist = [16, 15, 11, 4]                                      # the last distance last
    while True:
        last = b.read(1)
        if last and b.read(1):
            break
        nib = b.read(2)
        if nib == 3:
            # metadata
            if b.read(1):
                raise Bad
            nbytes = b.read(2)
            skip = 0
            for k in range(nbytes):
                v = b.read(8)
                if k + 1 == nbytes and nbytes > 1 and v == 0:
                    raise Bad
                skip |= v << (8 * k)
            if nbytes:
                skip += 1
            b.align()
            if b.pos + skip > len(data):
                raise Bad
            b.pos += skip
            if last:
                break
            continue
        nib += 4
        mlen = 0
        for k in range(nib):
            v = b.read(4)
            if k + 1 == nib and nib > 4 and v == 0:
                raise Bad
            mlen |= v << (4 * k)
        mlen += 1
        if len(out) + mlen > limit:
            raise Bad
        if not last and b.read(1):
            # uncompressed
            b.align()
            if b.pos + mlen > len(data):
                raise Bad
            out += data[b.pos:b.pos + mlen]
            b.pos += mlen
            continue
        end = len(out) + mlen
        cats = [Category(b) for _ in range(3)]
        npostfix = b.read(2)
        ndirect = b.read(4) << npostfix
        modes = [b.read(2) for _ in range(cats[0].n)]
        ntreesl = read_count(b)
        cmapl = read_context_map(b, 64 * cats[0].n, ntreesl)
        ntreesd = read_count(b)
        cmapd = read_context_map(b, 4 * cats[2].n, ntreesd)
        lcodes = [read_code(b, 256) for _ in range(ntreesl)]
        icodes = [read_code(b, 704) for _ in range(cats[1].n)]
        dsize = 16 + ndirect + (48 << npostfix)
        dcodes = [read_code(b, dsize) for _ in range(ntreesd)]
        while len(out) < end:
            cats[1].next(b)
            cmd = icodes[cats[1].type].read(b)
            ib, cb = CELLS[cmd >> 6]
            ic, cc = ib + ((cmd >> 3) & 7), cb + (cmd & 7)
            ilen = INS_OFF[ic] + b.read(INS_BITS[ic])
            clen = COPY_OFF[cc] + b.read(COPY_BITS[cc])
            for _ in range(ilen):
                cats[0].next(b)
                p1 = out[-1] if out else 0
                p2 = out[-2] if len(out) > 1 else 0
                mode = modes[cats[0].type]
                if mode == 0:
                    ctx = p1 & 0x3F
                elif mode == 1:
                    ctx = p1 >> 2
                elif mode == 2:
                    ctx = T.LUT0[p1] | T.LUT1[p2]
                else:
                    ctx = (T.LUT2[p1] << 3) | T.LUT2[p2]
                out.append(lcodes[cmapl[64 * cats[0].type + ctx]].read(b))
                if len(out) == end:
                    break
            if len(out) >= end:
                break
            if cmd < 128:
                dcode = 0
            else:
                cats[2].next(b)
                ctx = 3 if clen > 4 else clen - 2
                dcode = dcodes[cmapd[4 * cats[2].type + ctx]].read(b)
            if dcode < 16:
                which, delta = SHORT[dcode]
                d = dist[3 - which] + delta
                if d <= 0:
                    raise Bad
            elif dcode < 16 + ndirect:
                d = dcode - 15
            else:
                x = dcode - ndirect - 16
                nbits = 1 + (x >> (npostfix + 1))
                hcode = x >> npostfix
                lcode = x & ((1 << npostfix) - 1)
                off = ((2 + (hcode & 1)) << nbits) - 4
                d = ((off + b.read(nbits)) << npostfix) + lcode + ndirect + 1
            mx = min(len(out), maxback)
            if d > mx:
                # the static dictionary
                if not 4 <= clen <= 24:
                    raise Bad
                off = d - mx - 1
                nd = T.NDBITS[clen]
                word = off & ((1 << nd) - 1)
                t = off >> nd
                if t >= 121:
                    raise Bad
                at = T.DICT_OFFSETS[clen] + word * clen
                piece = transform(dictionary()[at:at + clen], t)
                if len(out) + len(piece) > end:
                    raise Bad
                out += piece
            else:
                if dcode:
                    dist = dist[1:] + [d]
                if len(out) + clen > end:
                    raise Bad
                for _ in range(clen):
                    out.append(out[-d])
        if last:
            break
    # the end: zero padding to the byte, nothing after it
    b.align()
    if b.pos != len(data):
        raise Bad
    return bytes(out)

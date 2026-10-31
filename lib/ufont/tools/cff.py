"""CFF outlines (OpenType 'CFF ' tables, Type 2 charstrings) - the model sfnt/cff.asm follows.

    c = CFF(table bytes)
    c.outline(glyph) -> [('move', x, y), ('line', x, y), ('cubic', x1, y1, x2, y2, x3, y3),
                         ('close',)] in font units, y up, or [] (none / damaged)

The table: header, Name / Top DICT / String / Global Subr INDEXes; from the Top DICT the
CharStrings INDEX, the Private DICT (its local Subrs) - or for a CID-keyed font (ROS) the FDArray
and FDSelect (formats 0 and 3), each Font DICT's Private DICT. Charstrings: every Type 2 operator
that draws (moves, lines, curves, the four flexes), stems and hint masks counted to skip their
bytes, the advance width before the first stack-clearing operator dropped, subroutines (local and
global, biased, 10 deep), endchar. Numbers: integers and 16.16 fixed, as doubles; points are summed
in the order the operators give them. seac (endchar's accent form) and the deprecated arithmetic
operators end the glyph.

Development-machine tooling only; not part of any OS image.
"""
import struct

MAX_STACK = 48
MAX_DEPTH = 10


def index(data, p):
    """-> ([(start, end)] of the items, the offset after the INDEX); None if damaged."""
    if p + 2 > len(data):
        return None
    count = struct.unpack_from('>H', data, p)[0]
    if count == 0:
        return [], p + 2
    if p + 3 > len(data):
        return None
    osz = data[p + 2]
    if not 1 <= osz <= 4:
        return None
    base = p + 3 + (count + 1) * osz - 1
    if p + 3 + (count + 1) * osz > len(data):
        return None
    offs = []
    for i in range(count + 1):
        q = p + 3 + i * osz
        offs.append(int.from_bytes(data[q:q + osz], 'big'))
    items = []
    for i in range(count):
        a, b = base + offs[i], base + offs[i + 1]
        if offs[i] < 1 or b < a or b > len(data):
            return None
        items.append((a, b))
    return items, base + offs[count]


def dict_parse(data, a, b):
    """A DICT -> {operator: [operands]} (12 x as 1200 + x); reals as floats."""
    out, ops = {}, []
    p = a
    while p < b:
        b0 = data[p]
        if b0 <= 21:
            if b0 == 12:
                if p + 1 >= b:
                    break
                op = 1200 + data[p + 1]
                p += 2
            else:
                op = b0
                p += 1
            out[op] = ops
            ops = []
        elif b0 == 28:
            if p + 3 > b:
                break
            ops.append(struct.unpack_from('>h', data, p + 1)[0])
            p += 3
        elif b0 == 29:
            if p + 5 > b:
                break
            ops.append(struct.unpack_from('>i', data, p + 1)[0])
            p += 5
        elif b0 == 30:
            # a real: nibbles to the 0xF end
            s, p = '', p + 1
            done = False
            while p < b and not done:
                for nib in (data[p] >> 4, data[p] & 15):
                    if nib <= 9:
                        s += str(nib)
                    elif nib == 0xA:
                        s += '.'
                    elif nib == 0xB:
                        s += 'E'
                    elif nib == 0xC:
                        s += 'E-'
                    elif nib == 0xE:
                        s += '-'
                    elif nib == 0xF:
                        done = True
                        break
                p += 1
            try:
                ops.append(float(s))
            except ValueError:
                ops.append(0.0)
        elif 32 <= b0 <= 246:
            ops.append(b0 - 139)
            p += 1
        elif 247 <= b0 <= 250:
            if p + 2 > b:
                break
            ops.append((b0 - 247) * 256 + data[p + 1] + 108)
            p += 2
        elif 251 <= b0 <= 254:
            if p + 2 > b:
                break
            ops.append(-(b0 - 251) * 256 - data[p + 1] - 108)
            p += 2
        else:
            p += 1                                      # reserved
    return out


def bias(n):
    return 107 if n < 1240 else 1131 if n < 33900 else 32768


class CFF:
    def __init__(self, data):
        self.data = data
        self.ok = False
        if len(data) < 4 or data[0] != 1:
            return
        p = data[2]
        r = index(data, p)                              # Name
        if r is None:
            return
        r = index(data, r[1])                           # Top DICT
        if r is None or not r[0]:
            return
        top = dict_parse(data, *r[0][0])
        r = index(data, r[1])                           # String
        if r is None:
            return
        r = index(data, r[1])                           # Global Subrs
        if r is None:
            return
        self.gsubrs = r[0]
        if 17 not in top or not top[17]:
            return
        cs = index(data, int(top[17][0]))
        if cs is None:
            return
        self.cs = cs[0]
        self.cid = 1230 in top
        if self.cid:
            fda = index(data, int(top.get(1236, [0])[0])) if 1236 in top else None
            if fda is None or 1237 not in top:
                return
            self.fds = [self.private(*dict_parse(data, a, b).get(18, [0, 0])[:2]) for a, b in fda[0]]
            self.fdselect = int(top[1237][0])
        else:
            self.local = self.private(*top.get(18, [0, 0])[:2])
        self.ok = True

    def private(self, size=0, off=0):
        """A Private DICT -> its local Subrs."""
        size, off = int(size), int(off)
        if size <= 0 or off <= 0 or off + size > len(self.data):
            return []
        pd = dict_parse(self.data, off, off + size)
        if 19 not in pd or not pd[19]:
            return []
        r = index(self.data, off + int(pd[19][0]))
        return r[0] if r else []

    def fd_of(self, gid):
        d, p = self.data, self.fdselect
        if p >= len(d):
            return None
        fmt = d[p]
        if fmt == 0:
            return d[p + 1 + gid] if p + 1 + gid < len(d) else None
        if fmt == 3:
            if p + 3 > len(d):
                return None
            n = struct.unpack_from('>H', d, p + 1)[0]
            for k in range(n):
                q = p + 3 + k * 3
                if q + 5 > len(d):
                    return None
                first = struct.unpack_from('>H', d, q)[0]
                nxt = struct.unpack_from('>H', d, q + 3)[0]
                if first <= gid < nxt:
                    return d[q + 2]
            return None
        return None

    def outline(self, gid):
        if not self.ok or not 0 <= gid < len(self.cs):
            return []
        if self.cid:
            fd = self.fd_of(gid)
            if fd is None or fd >= len(self.fds):
                return []
            local = self.fds[fd]
        else:
            local = self.local
        st = _State()
        st.local, st.gsubrs = local, self.gsubrs
        try:
            self._run(st, *self.cs[gid], 0)
        except _End:
            pass
        if st.open:
            st.out.append(('close',))
        return st.out

    def _run(self, st, a, b, depth):
        d = self.data
        p = a
        stack = st.stack
        while p < b:
            b0 = d[p]
            if b0 >= 32 or b0 == 28:
                if b0 == 28:
                    if p + 3 > b:
                        raise _End
                    v = float(struct.unpack_from('>h', d, p + 1)[0])
                    p += 3
                elif b0 <= 246:
                    v = float(b0 - 139)
                    p += 1
                elif b0 <= 250:
                    if p + 2 > b:
                        raise _End
                    v = float((b0 - 247) * 256 + d[p + 1] + 108)
                    p += 2
                elif b0 <= 254:
                    if p + 2 > b:
                        raise _End
                    v = float(-(b0 - 251) * 256 - d[p + 1] - 108)
                    p += 2
                else:
                    if p + 5 > b:
                        raise _End
                    v = struct.unpack_from('>i', d, p + 1)[0] / 65536.0
                    p += 5
                if len(stack) >= MAX_STACK:
                    raise _End
                stack.append(v)
                continue
            op = b0
            p += 1
            if op == 12:
                if p >= b:
                    raise _End
                op = 1200 + d[p]
                p += 1
            if op in (1, 3, 18, 23):                    # hstem vstem hstemhm vstemhm
                st.width(len(stack) % 2 == 1)
                st.stems += len(stack) // 2
                stack.clear()
            elif op in (19, 20):                        # hintmask cntrmask
                st.width(len(stack) % 2 == 1)
                st.stems += len(stack) // 2
                stack.clear()
                p += (st.stems + 7) // 8
            elif op == 21:                              # rmoveto
                st.width(len(stack) > 2)
                if len(stack) < 2:
                    raise _End
                st.move(stack[-2], stack[-1])
                stack.clear()
            elif op == 22:                              # hmoveto
                st.width(len(stack) > 1)
                if len(stack) < 1:
                    raise _End
                st.move(stack[-1], 0.0)
                stack.clear()
            elif op == 4:                               # vmoveto
                st.width(len(stack) > 1)
                if len(stack) < 1:
                    raise _End
                st.move(0.0, stack[-1])
                stack.clear()
            elif op == 5:                               # rlineto
                for k in range(0, len(stack) - 1, 2):
                    st.line(stack[k], stack[k + 1])
                stack.clear()
            elif op in (6, 7):                          # hlineto vlineto
                horiz = op == 6
                for v in stack:
                    st.line(v, 0.0) if horiz else st.line(0.0, v)
                    horiz = not horiz
                stack.clear()
            elif op == 8:                               # rrcurveto
                for k in range(0, len(stack) - 5, 6):
                    st.curve(*stack[k:k + 6])
                stack.clear()
            elif op == 27:                              # hhcurveto
                k, dy1 = 0, 0.0
                if len(stack) % 2:
                    dy1, k = stack[0], 1
                while k + 4 <= len(stack):
                    st.curve(stack[k], dy1, stack[k + 1], stack[k + 2], stack[k + 3], 0.0)
                    dy1 = 0.0
                    k += 4
                stack.clear()
            elif op == 26:                              # vvcurveto
                k, dx1 = 0, 0.0
                if len(stack) % 2:
                    dx1, k = stack[0], 1
                while k + 4 <= len(stack):
                    st.curve(dx1, stack[k], stack[k + 1], stack[k + 2], 0.0, stack[k + 3])
                    dx1 = 0.0
                    k += 4
                stack.clear()
            elif op in (31, 30):                        # hvcurveto vhcurveto
                horiz = op == 31
                k, n = 0, len(stack)
                while k + 4 <= n:
                    last = 0.0
                    if n - k == 5:
                        last = stack[k + 4]
                    if horiz:
                        st.curve(stack[k], 0.0, stack[k + 1], stack[k + 2], last, stack[k + 3])
                    else:
                        st.curve(0.0, stack[k], stack[k + 1], stack[k + 2], stack[k + 3], last)
                    horiz = not horiz
                    k += 4
                stack.clear()
            elif op == 24:                              # rcurveline
                k = 0
                while k + 8 <= len(stack):
                    st.curve(*stack[k:k + 6])
                    k += 6
                if k + 2 <= len(stack):
                    st.line(stack[k], stack[k + 1])
                stack.clear()
            elif op == 25:                              # rlinecurve
                k = 0
                while k + 8 <= len(stack):
                    st.line(stack[k], stack[k + 1])
                    k += 2
                if k + 6 <= len(stack):
                    st.curve(*stack[k:k + 6])
                stack.clear()
            elif op == 1235:                            # flex
                if len(stack) >= 12:
                    st.curve(*stack[0:6])
                    st.curve(*stack[6:12])
                stack.clear()
            elif op == 1234:                            # hflex
                if len(stack) >= 7:
                    s = stack
                    st.curve(s[0], 0.0, s[1], s[2], s[3], 0.0)
                    st.curve(s[4], 0.0, s[5], 0.0 - s[2], s[6], 0.0)
                stack.clear()
            elif op == 1236:                            # hflex1
                if len(stack) >= 9:
                    s = stack
                    st.curve(s[0], s[1], s[2], s[3], s[4], 0.0)
                    st.curve(s[5], 0.0, s[6], s[7], s[8], 0.0 - (s[1] + s[3] + s[7]))
                stack.clear()
            elif op == 1237:                            # flex1
                if len(stack) >= 11:
                    s = stack
                    dx = s[0] + s[2] + s[4] + s[6] + s[8]
                    dy = s[1] + s[3] + s[5] + s[7] + s[9]
                    st.curve(*s[0:6])
                    if abs(dx) > abs(dy):
                        st.curve(s[6], s[7], s[8], s[9], s[10], 0.0 - dy)
                    else:
                        st.curve(s[6], s[7], s[8], s[9], 0.0 - dx, s[10])
                stack.clear()
            elif op in (10, 29):                        # callsubr callgsubr
                if not stack or depth >= MAX_DEPTH:
                    raise _End
                subrs = st.local if op == 10 else st.gsubrs
                i = int(stack.pop()) + bias(len(subrs))
                if not 0 <= i < len(subrs):
                    raise _End
                self._run(st, *subrs[i], depth + 1)
            elif op == 11:                              # return
                return
            elif op == 14:                              # endchar (seac: the end too)
                raise _End
            else:
                raise _End                              # arithmetic, reserved


class _End(Exception):
    pass


class _State:
    def __init__(self):
        self.stack, self.out = [], []
        self.x = self.y = 0.0
        self.open = False
        self.stems = 0
        self.widthed = False

    def width(self, extra):
        """The first stack-clearing operator: an extra first operand is the advance width."""
        if not self.widthed:
            self.widthed = True
            if extra:
                del self.stack[0]

    def move(self, dx, dy):
        if self.open:
            self.out.append(('close',))
        self.x = self.x + dx
        self.y = self.y + dy
        self.out.append(('move', self.x, self.y))
        self.open = True

    def start(self):
        if not self.open:
            self.out.append(('move', self.x, self.y))
            self.open = True

    def line(self, dx, dy):
        self.start()
        self.x = self.x + dx
        self.y = self.y + dy
        self.out.append(('line', self.x, self.y))

    def curve(self, dxa, dya, dxb, dyb, dxc, dyc):
        self.start()
        x1, y1 = self.x + dxa, self.y + dya
        x2, y2 = x1 + dxb, y1 + dyb
        self.x, self.y = x2 + dxc, y2 + dyc
        self.out.append(('cubic', x1, y1, x2, y2, self.x, self.y))

"""A small AML encoder for tests: builds definition blocks term by term.

Every function returns bytes. Names are text ("\\_SB.PCI0", "^FOO", "X");
short segments are padded with '_'.
"""
import struct

BS = chr(92)        # the root prefix character


def pkglen(body_len):
    """PkgLength for a body of body_len bytes (the length counts itself)."""
    for n in range(1, 5):
        total = body_len + n
        if n == 1 and total <= 0x3F:
            return bytes([total])
        if n > 1 and total < (1 << (4 + 8 * (n - 1))):
            out = [((n - 1) << 6) | (total & 0x0F)]
            rest = total >> 4
            for _ in range(n - 1):
                out.append(rest & 0xFF)
                rest >>= 8
            return bytes(out)
    raise ValueError("too long")


def field_len(bits):
    """A PkgLength used as a number (field widths)."""
    if bits <= 0x3F:
        return bytes([bits])
    n = 1
    while bits >= (1 << (4 + 8 * n)):
        n += 1
    out = [(n << 6) | (bits & 0x0F)]
    rest = bits >> 4
    for _ in range(n):
        out.append(rest & 0xFF)
        rest >>= 8
    return bytes(out)


def seg(s):
    s = s.ljust(4, "_")
    assert len(s) == 4, s
    return s.encode()


def name(text):
    out = b""
    if text.startswith(BS):
        out += b"\\"
        text = text[1:]
    while text.startswith("^"):
        out += b"^"
        text = text[1:]
    segs = [s for s in text.split(".") if s] if text else []
    if not segs:
        return out + b"\x00"
    if len(segs) == 1:
        return out + seg(segs[0])
    if len(segs) == 2:
        return out + b"\x2E" + seg(segs[0]) + seg(segs[1])
    return out + b"\x2F" + bytes([len(segs)]) + b"".join(seg(s) for s in segs)


def pkg(op, *parts):
    body = b"".join(parts)
    return op + pkglen(len(body)) + body


# ---- data -----------------------------------------------------------------------
def Int(v):
    if v == 0:
        return b"\x00"
    if v == 1:
        return b"\x01"
    if v == (1 << 64) - 1:
        return b"\xFF"
    if v < 0x100:
        return b"\x0A" + bytes([v])
    if v < 0x10000:
        return b"\x0B" + struct.pack("<H", v)
    if v < 0x100000000:
        return b"\x0C" + struct.pack("<I", v)
    return b"\x0E" + struct.pack("<Q", v)


Zero, One, Ones = b"\x00", b"\x01", b"\xFF"


def Str(s):
    return b"\x0D" + s.encode() + b"\x00"


def Buf(data, size=None):
    size = len(data) if size is None else size
    return pkg(b"\x11", Int(size), bytes(data))


def Pkg(*elems):
    return pkg(b"\x12", bytes([len(elems)]), *elems)


def VarPkg(count, *elems):
    return pkg(b"\x13", count, *elems)


def Local(i):
    return bytes([0x60 + i])


def Arg(i):
    return bytes([0x68 + i])


Null = b"\x00"          # a null target
Debug = b"\x5B\x31"


def N(text):
    """A name used as an operand or target."""
    return name(text)


def Call(text, *args):
    return name(text) + b"".join(args)


# ---- named objects ------------------------------------------------------------------
def Name(text, obj):
    return b"\x08" + name(text) + obj


def Scope(text, *terms):
    return pkg(b"\x10", name(text), *terms)


def Device(text, *terms):
    return pkg(b"\x5B\x82", name(text), *terms)


def Processor(text, pid, *terms):
    return pkg(b"\x5B\x83", name(text), bytes([pid]), struct.pack("<I", 0), b"\x00", *terms)


def ThermalZone(text, *terms):
    return pkg(b"\x5B\x85", name(text), *terms)


def Method(text, nargs, *terms, serialized=False):
    flags = (nargs & 7) | (8 if serialized else 0)
    return pkg(b"\x14", name(text), bytes([flags]), *terms)


def Alias(src, dst):
    return b"\x06" + name(src) + name(dst)


def External(text, objtype, nargs=0):
    return b"\x15" + name(text) + bytes([objtype, nargs])


def Mutex(text):
    return b"\x5B\x01" + name(text) + b"\x00"


def Event(text):
    return b"\x5B\x02" + name(text)


def OpRegion(text, space, offset, length):
    return b"\x5B\x80" + name(text) + bytes([space]) + Int(offset) + Int(length)


def F(fname, bits):
    return seg(fname) + field_len(bits)


def Reserved(bits):
    return b"\x00" + field_len(bits)


def Access(acctype, attrib=0):
    return b"\x01" + bytes([acctype, attrib])


ANY, BYTE, WORD, DWORD, QWORD = 0, 1, 2, 3, 4
PRESERVE, ONES, ZEROS = 0x00, 0x20, 0x40


def Field(region, flags, *entries):
    return pkg(b"\x5B\x81", name(region), bytes([flags]), *entries)


def IndexField(index, data, flags, *entries):
    return pkg(b"\x5B\x86", name(index), name(data), bytes([flags]), *entries)


def BankField(region, bank, value, flags, *entries):
    return pkg(b"\x5B\x87", name(region), name(bank), value, bytes([flags]), *entries)


def CreateDWordField(src, idx, text):
    return b"\x8A" + src + idx + name(text)


def CreateWordField(src, idx, text):
    return b"\x8B" + src + idx + name(text)


def CreateByteField(src, idx, text):
    return b"\x8C" + src + idx + name(text)


def CreateBitField(src, idx, text):
    return b"\x8D" + src + idx + name(text)


def CreateQWordField(src, idx, text):
    return b"\x8F" + src + idx + name(text)


def CreateField(src, bit, nbits, text):
    return b"\x5B\x13" + src + bit + nbits + name(text)


# ---- statements ----------------------------------------------------------------------
def If(pred, *terms):
    return pkg(b"\xA0", pred, *terms)


def Else(*terms):
    return pkg(b"\xA1", *terms)


def While(pred, *terms):
    return pkg(b"\xA2", pred, *terms)


def Return(x):
    return b"\xA4" + x


Break, Continue, Noop = b"\xA5", b"\x9F", b"\xA3"


def Notify(obj, value):
    return b"\x86" + obj + value


def Sleep(ms):
    return b"\x5B\x22" + ms


def Fatal():
    return b"\x5B\x32\x00" + struct.pack("<I", 0) + Zero


# ---- expressions ---------------------------------------------------------------------
def Store(src, dst):
    return b"\x70" + src + dst


def _bin(op):
    return lambda a, b, t=Null: bytes([op]) + a + b + t


Add, Subtract, Multiply = _bin(0x72), _bin(0x74), _bin(0x77)
ShiftLeft, ShiftRight = _bin(0x79), _bin(0x7A)
And, NAnd, Or, NOr, XOr, Mod = _bin(0x7B), _bin(0x7C), _bin(0x7D), _bin(0x7E), _bin(0x7F), _bin(0x85)
Concatenate = _bin(0x73)


def Divide(a, b, rem=Null, quot=Null):
    return b"\x78" + a + b + rem + quot


def Increment(t):
    return b"\x75" + t


def Decrement(t):
    return b"\x76" + t


def Not(a, t=Null):
    return b"\x80" + a + t


def FindSetLeftBit(a, t=Null):
    return b"\x81" + a + t


def FindSetRightBit(a, t=Null):
    return b"\x82" + a + t


def RefOf(t):
    return b"\x71" + t


def DerefOf(x):
    return b"\x83" + x


def SizeOf(x):
    return b"\x87" + x


def Index(src, idx, t=Null):
    return b"\x88" + src + idx + t


def ObjectType(x):
    return b"\x8E" + x


def CondRefOf(x, t=Null):
    return b"\x5B\x12" + x + t


def LAnd(a, b):
    return b"\x90" + a + b


def LOr(a, b):
    return b"\x91" + a + b


def LNot(a):
    return b"\x92" + a


def LEqual(a, b):
    return b"\x93" + a + b


def LGreater(a, b):
    return b"\x94" + a + b


def LLess(a, b):
    return b"\x95" + a + b


def LNotEqual(a, b):
    return b"\x92\x93" + a + b


def LLessEqual(a, b):
    return b"\x92\x94" + a + b


def LGreaterEqual(a, b):
    return b"\x92\x95" + a + b


def ToInteger(a, t=Null):
    return b"\x99" + a + t


def ToBuffer(a, t=Null):
    return b"\x96" + a + t


def ToString(a, length=Ones, t=Null):
    return b"\x9C" + a + length + t


def Mid(a, idx, length, t=Null):
    return b"\x9E" + a + idx + length + t


def CopyObject(a, t):
    return b"\x9D" + a + t


def Acquire(mutex, timeout=0xFFFF):
    return b"\x5B\x23" + name(mutex) + struct.pack("<H", timeout)


def Release(mutex):
    return b"\x5B\x27" + name(mutex)


def Match(*_):
    return b"\x89" + Zero      # not built: the interpreter refuses it


# ---- tables ---------------------------------------------------------------------------
def Table(*terms, sig="DSDT", revision=2):
    body = b"".join(terms)
    length = 36 + len(body)
    head = sig.encode() + struct.pack("<IBB", length, revision, 0) + b"TESTID" + b"TESTTBL " \
        + struct.pack("<I", 1) + b"TEST" + struct.pack("<I", 1)
    table = bytearray(head + body)
    table[9] = (-sum(table)) & 0xFF
    return bytes(table)

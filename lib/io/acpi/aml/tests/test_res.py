"""Resource template tests: every descriptor kind, _CRS, malformed input.

usage: python3 test_res.py path/to/aml.so
"""
import ctypes as C
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403

lib = C.CDLL(sys.argv[1])
EBADCODE, ENOTFOUND, ETYPE = 1, 3, 4


class Value(C.Structure):
    _fields_ = [("type", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint16),
                ("len", C.c_uint32), ("data", C.c_uint64)]


class Res(C.Structure):
    _fields_ = [("kind", C.c_uint8), ("flags", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint8),
                ("count", C.c_uint32), ("base", C.c_uint64), ("len", C.c_uint64), ("extra", C.c_uint64),
                ("source", C.c_uint64), ("raw", C.c_uint64), ("raw_len", C.c_uint32), ("pad2", C.c_uint32)]


assert C.sizeof(Res) == 56
K_IRQ, DMA, IO, FIXED_IO, MEM24, MEM32, FIXED_MEM32, ADDRESS, EXT_IRQ = range(1, 10)
GPIO_INT, GPIO_IO, I2C, SPI, UART, CSI2, REGISTER, FIXED_DMA, VENDOR, PIN, CLOCK, START_DEP, END_DEP = range(10, 23)
EDGE, LOW, SHARED, WAKE, BOTH = 1, 2, 4, 8, 16


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


aml_init = fn("aml_init", C.c_int32, C.c_void_p, C.c_uint64)
aml_load = fn("aml_load", C.c_int32, C.c_char_p)
aml_find = fn("aml_find", C.c_void_p, C.c_char_p)
aml_get_crs = fn("aml_get_crs", C.c_int32, C.c_void_p, C.POINTER(Value))
aml_res_next = fn("aml_res_next", C.c_int32, C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32), C.POINTER(Res))

# ---- descriptors, byte by byte from the specification -------------------------------


def small(t, data):
    return bytes([(t << 3) | len(data)]) + data


def large(t, data):
    return bytes([0x80 | t]) + struct.pack("<H", len(data)) + data


END = b"\x79\x00"


def IRQNoFlags(*irqs):
    return small(4, struct.pack("<H", sum(1 << i for i in irqs)))


def IRQ(irqs, edge, low, shared=False, wake=False):
    f = (1 if edge else 0) | (8 if low else 0) | (0x10 if shared else 0) | (0x20 if wake else 0)
    return small(4, struct.pack("<HB", sum(1 << i for i in irqs), f))


def DMA_(chans, flags):
    return small(5, bytes([sum(1 << c for c in chans), flags]))


def IO_(decode16, lo, hi, align, length):
    return small(8, struct.pack("<BHHBB", decode16, lo, hi, align, length))


def FixedIO(base, length):
    return small(9, struct.pack("<HB", base, length))


def FixedDMA(line, chan, width):
    return small(10, struct.pack("<HHB", line, chan, width))


def VendorShort(data):
    return small(14, bytes(data))


def StartDep():
    return small(6, b"")


def EndDep():
    return small(7, b"")


def Memory24(rw, lo, hi, align, length):
    return large(1, struct.pack("<BHHHH", rw, lo >> 8, hi >> 8, align, length >> 8))


def Register(space, width, offset, size, addr):
    return large(2, struct.pack("<BBBBQ", space, width, offset, size, addr))


def Memory32(rw, lo, hi, align, length):
    return large(5, struct.pack("<BIIII", rw, lo, hi, align, length))


def Memory32Fixed(rw, base, length):
    return large(6, struct.pack("<BII", rw, base, length))


def _source(src):
    return b"" if src is None else b"\x00" + src.encode() + b"\x00"


def WordAddr(rtype, lo, length, translation=0, src=None):
    return large(8, struct.pack("<BBBHHHHH", rtype, 0x0C, 0, 0, lo, lo + length - 1, translation, length) + _source(src))


def DWordAddr(rtype, lo, length, translation=0, src=None):
    return large(7, struct.pack("<BBBIIIII", rtype, 0x0C, 1, 0, lo, lo + length - 1, translation, length) + _source(src))


def QWordAddr(rtype, lo, length, translation=0):
    return large(10, struct.pack("<BBBQQQQQ", rtype, 0x0C, 1, 0, lo, lo + length - 1, translation, length))


def ExtAddr(rtype, lo, length, translation=0):
    return large(11, struct.pack("<BBBBBQQQQQQ", rtype, 0x0C, 1, 1, 0, 0, lo, lo + length - 1, translation, length, 0))


def Interrupt(irqs, edge, low, shared=False, wake=False, src=None):
    f = 1 | (2 if edge else 0) | (4 if low else 0) | (8 if shared else 0) | (0x10 if wake else 0)
    return large(9, struct.pack("<BB", f, len(irqs)) + b"".join(struct.pack("<I", i) for i in irqs) + _source(src))


def Gpio(conn, flags, pincfg, debounce, pins, src, vendor=b""):
    fixed = 23
    pin_table = fixed
    name_off = pin_table + 2 * len(pins)
    name = src.encode() + b"\x00"
    vendor_off = name_off + len(name) if vendor else 0
    data = struct.pack("<BBHHBHHHBHHH", 1, conn, 0, flags, pincfg, 0, debounce, pin_table, 0,
                       name_off, vendor_off, len(vendor))
    data += b"".join(struct.pack("<H", p) for p in pins) + name + vendor
    return large(12, data)


def GpioInt(edge, polarity, shared, wake, pins, src, debounce=0, pincfg=1):
    flags = (1 if edge else 0) | (polarity << 1) | (8 if shared else 0) | (0x10 if wake else 0)
    return Gpio(0, flags, pincfg, debounce, pins, src)


def GpioIo(restriction, pins, src):
    return Gpio(1, restriction, 0, 0, pins, src)


def Serial(bustype, tflags, tdata, src):
    return large(14, struct.pack("<BBBBHBH", 2, 0, bustype, 2, tflags, 1, len(tdata)) + tdata
                 + src.encode() + b"\x00")


def I2cBus(addr, speed, ten_bit, src):
    return Serial(1, 1 if ten_bit else 0, struct.pack("<IH", speed, addr), src)


def SpiBus(cs, speed, bits, phase, pol, src):
    return Serial(2, 0, struct.pack("<IBBBH", speed, bits, phase, pol, cs), src)


def UartBus(baud, rx, tx, parity, lines, src):
    return Serial(3, 0x30, struct.pack("<IHHBB", baud, rx, tx, parity, lines), src)


def decode(buf):
    """Every descriptor in a template, as Res copies; the final status."""
    raw = C.create_string_buffer(bytes(buf), len(buf))
    off = C.c_uint32(0)
    out = []
    while True:
        r = Res()
        st = aml_res_next(raw, len(buf), C.byref(off), C.byref(r))
        if st != 1:
            return out, st, raw
        out.append(r)
        if len(out) > 1000:
            return out, "runaway", raw


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def text(addr):
    return C.string_at(addr).decode() if addr else None


def pins(r):
    return list(struct.unpack("<%dH" % r.count, C.string_at(r.extra, 2 * r.count)))


# --- every kind ---------------------------------------------------------------------------
tmpl = (IRQNoFlags(1) + IRQ([3, 5], edge=False, low=True, shared=True, wake=True) + DMA_([2], 0x41)
        + IO_(1, 0x60, 0x60, 1, 1) + FixedIO(0x3F8, 8) + FixedDMA(5, 2, 1) + VendorShort([1, 2, 3])
        + StartDep() + Memory24(1, 0xD0000, 0xD0000, 1, 0x10000) + EndDep()
        + Register(1, 8, 0, 1, 0xB2) + Memory32(0, 0xFED00000, 0xFED00000, 1, 0x400)
        + Memory32Fixed(1, 0xFEE00000, 0x1000)
        + WordAddr(2, 0, 0x100) + DWordAddr(1, 0x0D00, 0xF300, src="\\_SB.PCI0")
        + QWordAddr(0, 0x400000000, 0x100000000, 0x10) + ExtAddr(0, 0x800000000, 0x1000)
        + Interrupt([0x1F], edge=True, low=False, wake=True, src="\\_SB.GSI0")
        + GpioInt(False, 1, False, True, [9], "\\_SB.GPIO", debounce=500)
        + GpioIo(1, [4, 5, 6], "\\_SB.GPI1")
        + I2cBus(0x2C, 400000, False, "\\_SB.I2CD") + SpiBus(1, 8000000, 8, 1, 0, "\\_SB.SPI0")
        + UartBus(115200, 64, 64, 0, 0x0F, "\\_SB.URT0") + END)
rs, st, keep = decode(tmpl)
check("end tag", st, 0)
check("descriptor kinds", [r.kind for r in rs],
      [K_IRQ, K_IRQ, DMA, IO, FIXED_IO, FIXED_DMA, VENDOR, START_DEP, MEM24, END_DEP, REGISTER, MEM32,
       FIXED_MEM32, ADDRESS, ADDRESS, ADDRESS, ADDRESS, EXT_IRQ, GPIO_INT, GPIO_IO, I2C, SPI, UART])
r = rs[0]
check("IRQ without flags: edge, active high", (r.base, r.count, r.extra, r.flags), (1, 1, 2, EDGE))
r = rs[1]
check("IRQ with flags", (r.base, r.count, r.extra, r.flags), (3, 2, 0x28, LOW | SHARED | WAKE))
check("DMA", (rs[2].base, rs[2].count, rs[2].sub), (2, 1, 0x41))
check("IO", (rs[3].base, rs[3].extra, rs[3].len, rs[3].sub), (0x60, 0x60, 1, 1))
check("fixed IO", (rs[4].base, rs[4].len), (0x3F8, 8))
check("fixed DMA", (rs[5].base, rs[5].len, rs[5].extra), (5, 2, 1))
check("vendor", rs[6].count, 3)
check("memory 24", (rs[8].base, rs[8].len, rs[8].flags), (0xD0000, 0x10000, 1))
check("generic register", (rs[10].sub, rs[10].base, rs[10].len, rs[10].extra), (1, 0xB2, 8, 1 << 8))
check("memory 32", (rs[11].base, rs[11].len, rs[11].flags), (0xFED00000, 0x400, 0))
check("fixed memory 32", (rs[12].base, rs[12].len, rs[12].flags), (0xFEE00000, 0x1000, 1))
check("word address (bus numbers)", (rs[13].sub, rs[13].base, rs[13].len), (2, 0, 0x100))
check("dword address (I/O) with source", (rs[14].sub, rs[14].base, rs[14].len, text(rs[14].source)),
      (1, 0x0D00, 0xF300, "\\_SB.PCI0"))
check("qword address (memory)", (rs[15].sub, rs[15].base, rs[15].len, rs[15].extra),
      (0, 0x400000000, 0x100000000, 0x10))
check("extended address", (rs[16].base, rs[16].len), (0x800000000, 0x1000))
r = rs[17]
check("extended interrupt", (r.base, r.count, r.flags, text(r.source)), (0x1F, 1, EDGE | WAKE, "\\_SB.GSI0"))
r = rs[18]
check("GPIO interrupt", (pins(r), r.flags, r.len & 0xFFFF, (r.len >> 16) & 0xFFFF, r.len >> 32, text(r.source)),
      ([9], LOW | WAKE, 0x12, 500, 1, "\\_SB.GPIO"))
r = rs[19]
check("GPIO I/O", (pins(r), r.base, r.len & 0xFFFF, text(r.source)), ([4, 5, 6], 4, 1, "\\_SB.GPI1"))
r = rs[20]
check("I2C", (r.base, r.len, r.flags, text(r.source)), (0x2C, 400000, 0, "\\_SB.I2CD"))
r = rs[21]
check("SPI", (r.base, r.len, r.extra, text(r.source)), (1, 8000000, 8 | 1 << 8, "\\_SB.SPI0"))
r = rs[22]
check("UART", (r.len, r.extra, r.base, text(r.source)), (115200, 64 | 64 << 16 | 0x0F << 40, 0x30, "\\_SB.URT0"))
check("raw pointers cover each descriptor", sum(r.raw_len for r in rs) + 2, len(tmpl))
check("10-bit I2C", decode(I2cBus(0x3FF, 100000, True, "\\_SB.I2C1") + END)[0][0].flags, 1)
check("GPIO interrupt on both edges",
      decode(GpioInt(True, 2, True, False, [1], "\\G") + END)[0][0].flags, EDGE | BOTH | SHARED)
check("no end tag: stops at the buffer's end", decode(FixedIO(0x60, 1))[1], 0)

# --- malformed ---------------------------------------------------------------------------
check("small descriptor past the end", decode(bytes([0x47, 1, 0x60]))[1], -EBADCODE)
check("large header past the end", decode(b"\x86\x09")[1], -EBADCODE)
check("large length past the end", decode(b"\x86\x09\x00" + b"\x00" * 4)[1], -EBADCODE)
check("IO too short", decode(small(8, b"\x01\x60\x00") + END)[1], -EBADCODE)
check("memory 32 too short", decode(large(5, b"\x00" * 10) + END)[1], -EBADCODE)
check("extended IRQ with no IRQs", decode(large(9, b"\x01\x00") + END)[1], -EBADCODE)
check("extended IRQ count past the end", decode(large(9, b"\x01\x03" + b"\x00" * 4) + END)[1], -EBADCODE)
bad = bytearray(GpioInt(False, 0, False, False, [1], "\\G"))
bad[3 + 11] = 5                         # pin table inside the fixed part
check("GPIO pin table inside the header", decode(bytes(bad) + END)[1], -EBADCODE)
bad = bytearray(GpioInt(False, 0, False, False, [1], "\\G"))
bad[3 + 14] = 0xF0                      # name past the descriptor
check("GPIO name past the descriptor", decode(bytes(bad) + END)[1], -EBADCODE)
bad = bytearray(I2cBus(1, 1, False, "\\X"))
bad[3 + 7] = 0x40                       # type data longer than the descriptor
check("serial type data past the end", decode(bytes(bad) + END)[1], -EBADCODE)
bad = bytearray(I2cBus(1, 1, False, "\\X"))
bad[-1] = ord("Z")                      # name with no NUL: not recorded
check("source name without a NUL is ignored", text(decode(bytes(bad) + END)[0][0].source), None)
check("unknown small type", decode(small(1, b"\x00") + END)[1], -EBADCODE)
check("unknown large type", decode(large(0x40, b"") + END)[1], -EBADCODE)

rng = random.Random(99)
for i in range(5000):
    b = bytearray(rng.getrandbits(8) for _ in range(rng.randint(1, 80)))
    if rng.random() < 0.5:
        b = bytearray(tmpl)
        for _ in range(rng.randint(1, 8)):
            b[rng.randrange(len(b))] = rng.getrandbits(8)
    rs_, st_, _k = decode(b)
    if st_ == "runaway":
        check("fuzz terminates", st_, "ends")
        break
    for r in rs_:
        if r.raw and not (C.addressof(_k) <= r.raw < C.addressof(_k) + len(b)):
            check("fuzz raw pointer in the buffer", hex(r.raw), "inside")
check("5000 random templates decode without a crash", True, True)

# --- _CRS through the interpreter ------------------------------------------------------
HEAP = C.create_string_buffer((1 << 20) + 16)
heap = (C.addressof(HEAP) + 15) & ~15
assert aml_init(heap, 1 << 20) == 0
touchpad = I2cBus(0x2C, 400000, False, "\\_SB.I2CD") + GpioInt(False, 1, False, True, [9], "\\_SB.GPIO") + END
SB = BS + "_SB"
t = C.create_string_buffer(Table(Scope(SB,
    Device("TPD0", Name("_HID", Str("MSFT0001")), Name("_CRS", Buf(touchpad))),
    Device("TPD1", Method("_CRS", 0, Name("RBUF", Buf(touchpad)), CreateWordField(N("RBUF"), Int(16), "ADDR"),
                          Store(Int(0x15), N("ADDR")), Return(N("RBUF")))),
    Device("NCRS"), Device("ICRS", Name("_CRS", Int(5))))))
check("load", aml_load(t), 0)
v = Value()
check("_CRS name", aml_get_crs(aml_find((SB + ".TPD0").encode()), C.byref(v)), 0)
rs, st, _k = decode(C.string_at(v.data, v.len))
check("touchpad resources", [(r.kind, r.base, r.len if r.kind == I2C else r.flags, text(r.source)) for r in rs],
      [(I2C, 0x2C, 400000, "\\_SB.I2CD"), (GPIO_INT, 9, LOW | WAKE, "\\_SB.GPIO")])
check("_CRS method that edits its template", aml_get_crs(aml_find((SB + ".TPD1").encode()), C.byref(v)), 0)
rs, st, _k = decode(C.string_at(v.data, v.len))
check("edited I2C address", rs[0].base, 0x15)
check("no _CRS", aml_get_crs(aml_find((SB + ".NCRS").encode()), C.byref(v)), -ENOTFOUND)
check("_CRS that is not a buffer", aml_get_crs(aml_find((SB + ".ICRS").encode()), C.byref(v)), -ETYPE)

print(f"test_res: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

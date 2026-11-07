"""HID core tests: report descriptors into fields, values out of reports.

usage: python3 test_hid.py path/to/input.so
"""
import ctypes as C
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

lib = C.CDLL(sys.argv[1])
EINVAL, ENOSPC, ERANGE = 22, 28, 34
INPUT, OUTPUT, FEATURE = 1, 2, 3
CONST, VAR, REL = 1, 2, 4


class Field(C.Structure):
    _fields_ = [("report_id", C.c_uint8), ("kind", C.c_uint8), ("flags", C.c_uint16),
                ("bit_offset", C.c_uint32), ("size", C.c_uint16), ("count", C.c_uint16),
                ("usage_min", C.c_uint32), ("usage_max", C.c_uint32),
                ("usage_list", C.c_uint16), ("usage_count", C.c_uint16),
                ("logical_min", C.c_int32), ("logical_max", C.c_int32),
                ("physical_min", C.c_int32), ("physical_max", C.c_int32),
                ("unit", C.c_uint32), ("unit_exp", C.c_int8), ("pad", C.c_uint8),
                ("collection", C.c_uint16), ("application", C.c_uint32)]


class Collection(C.Structure):
    _fields_ = [("usage", C.c_uint32), ("type", C.c_uint8), ("pad", C.c_uint8), ("parent", C.c_uint16)]


class Desc(C.Structure):
    _fields_ = [("field_count", C.c_uint32), ("usage_count", C.c_uint32), ("coll_count", C.c_uint32),
                ("uses_ids", C.c_uint32), ("report_bits", C.c_uint32 * (256 * 3)),
                ("fields", Field * 256), ("usages", C.c_uint32 * 1024), ("collections", Collection * 64)]


assert C.sizeof(Field) == 52 and C.sizeof(Collection) == 8


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


hid_parse = fn("hid_parse", C.c_int32, C.c_char_p, C.c_uint32, C.POINTER(Desc))
report_bits = fn("hid_report_bits", C.c_uint32, C.POINTER(Desc), C.c_uint32, C.c_uint32)
find_usage = fn("hid_find_usage", C.c_int32, C.POINTER(Desc), C.c_uint32, C.c_uint32,
                C.POINTER(C.c_void_p), C.POINTER(C.c_uint32))
field_usage = fn("hid_field_usage", C.c_uint32, C.POINTER(Desc), C.c_void_p, C.c_uint32)
hid_get = fn("hid_get", C.c_int32, C.c_char_p, C.c_uint32, C.c_void_p, C.c_uint32)
hid_get.restype = C.c_int32


from hid_gen import *  # noqa: E402,F401,F403


def parse(data):
    d = Desc()
    return hid_parse(bytes(data), len(data), C.byref(d)), d


def fields(d):
    return [d.fields[i] for i in range(d.field_count)]


def pack(bits):
    """[(value, size), ...] → bytes, LSB first."""
    v, off = 0, 0
    for value, size in bits:
        v |= (value & ((1 << size) - 1)) << off
        off += size
    return v.to_bytes((off + 7) // 8, "little")


# hid_get returns the status in RAX and the value in RDX: a 16-byte
# struct return reads both
class Pair(C.Structure):
    _fields_ = [("status", C.c_int64), ("value", C.c_int64)]


hid_get_pair = fn("hid_get", Pair, C.c_char_p, C.c_uint32, C.c_void_p, C.c_uint32)


def hid_get_value(report, f, i=0):
    p = hid_get_pair(report, len(report), C.addressof(f), i)
    st = C.c_int32(p.status & 0xFFFFFFFF).value
    return ("error", -st) if st else p.value


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# --- boot keyboard -------------------------------------------------------------------------
st, d = parse(boot_keyboard)
check("keyboard parses", st, 0)
fs = fields(d)
check("keyboard fields (padding is not a field)", [(f.kind, f.flags, f.size, f.count) for f in fs],
      [(INPUT, VAR, 1, 8), (OUTPUT, VAR, 1, 5), (INPUT, 0, 8, 6)])
check("modifier usages", (hex(fs[0].usage_min), hex(fs[0].usage_max)), (hex(0x700E0), hex(0x700E7)))
check("LED usages", (hex(fs[1].usage_min), hex(fs[1].usage_max)), (hex(0x80001), hex(0x80005)))
check("key array after the reserved byte", (fs[2].bit_offset, fs[2].logical_max), (16, 101))
check("report lengths", (report_bits(d, 0, INPUT), report_bits(d, 0, OUTPUT), report_bits(d, 0, FEATURE)),
      (64, 8, 0))
check("no report IDs", d.uses_ids, 0)
check("application", hex(fs[0].application), hex(0x10006))
report = pack([(0b00000010, 8), (0, 8), (4, 8), (5, 8), (0, 8), (0, 8), (0, 8), (0, 8)])   # shift, a, b
check("left shift bit", [hid_get_value(report, fs[0], i) for i in range(8)], [0, 1, 0, 0, 0, 0, 0, 0])
check("pressed keys", [hid_get_value(report, fs[2], i) for i in range(3)], [4, 5, 0])
check("element past the field", hid_get_value(report, fs[2], 6), ("error", ERANGE))
check("report too short", hid_get_value(report[:3], fs[2], 1), ("error", ERANGE))
fp, idx = C.c_void_p(0), C.c_uint32(0)
check("find left shift", (find_usage(C.byref(d), INPUT, 0x700E1, C.byref(fp), C.byref(idx)), idx.value), (1, 1))
check("find in a range only variables", find_usage(C.byref(d), INPUT, 0x70004, C.byref(C.c_void_p(0)),
                                                   C.byref(idx)), 0)

# --- mouse --------------------------------------------------------------------------------------
st, d = parse(mouse)
fs = fields(d)
check("mouse parses", (st, len(fs)), (0, 2))
check("collections: application, physical inside it",
      [(d.collections[i].usage, d.collections[i].type, d.collections[i].parent) for i in range(d.coll_count)],
      [(0x10002, 1, 0xFFFF), (0x10001, 0, 0)])
check("axes listed", [hex(field_usage(C.byref(d), C.addressof(fs[1]), i)) for i in range(4)],
      ["0x10030", "0x10031", "0x10038", "0x10038"])
check("relative axes", fs[1].flags, VAR | REL)
report = pack([(0b101, 3), (0, 5), (-5, 8), (7, 8), (-1, 8)])
check("buttons", [hid_get_value(report, fs[0], i) for i in range(3)], [1, 0, 1])
check("signed motion", [hid_get_value(report, fs[1], i) for i in range(3)], [-5, 7, -1])

# --- touchpad -----------------------------------------------------------------------------------
st, d = parse(touchpad)
fs = fields(d)
check("touchpad parses", st, 0)
check("report IDs", (d.uses_ids, report_bits(d, 1, INPUT), report_bits(d, 2, FEATURE), report_bits(d, 3, FEATURE)),
      (1, 5 * 48 + 16 + 8 + 8, 8, 8))
xs = []
fp = C.c_void_p(0)
while find_usage(C.byref(d), INPUT, 0x10030, C.byref(fp), C.byref(idx)):
    xs.append(Field.from_address(fp.value))
check("five X fields, one per finger", [f.bit_offset for f in xs], [16, 64, 112, 160, 208])
check("X range, units, physical size", (xs[0].logical_max, xs[0].physical_max, xs[0].unit, xs[0].unit_exp),
      (4095, 1220, 0x11, -2))
ys = []
fp = C.c_void_p(0)
while find_usage(C.byref(d), INPUT, 0x10031, C.byref(fp), C.byref(idx)):
    ys.append(Field.from_address(fp.value))
check("Y range after Push and Pop", (ys[0].logical_max, ys[0].physical_max, ys[1].logical_max), (2470, 780, 2470))
ids = []
fp = C.c_void_p(0)
while find_usage(C.byref(d), INPUT, 0xD0051, C.byref(fp), C.byref(idx)):
    ids.append(Field.from_address(fp.value))
check("Pop restores the pushed size and range for the next finger",
      [(f.size, f.logical_max) for f in ids], [(8, 127)] * 5)
tips = []
fp = C.c_void_p(0)
while find_usage(C.byref(d), INPUT, 0xD0042, C.byref(fp), C.byref(idx)):
    tips.append(Field.from_address(fp.value))
check("tip switches", len(tips), 5)
check("finger collections", [d.collections[xs[i].collection].usage for i in range(2)], [0xD0022, 0xD0022])
check("touchpad application", hex(xs[0].application), hex(0xD0005))
fp = C.c_void_p(0)
check("input mode feature", (find_usage(C.byref(d), FEATURE, 0xD0052, C.byref(fp), C.byref(idx)),
                             Field.from_address(fp.value).report_id,
                             hex(Field.from_address(fp.value).application)), (1, 3, hex(0xD000E)))
fp = C.c_void_p(0)
find_usage(C.byref(d), INPUT, 0xD0054, C.byref(fp), C.byref(idx))
count_field = Field.from_address(fp.value)
fingers = [(1, 1, 0, 3, 1000, 2000), (1, 1, 0, 5, 3000, 100)] + [(0, 0, 0, 0, 0, 0)] * 3
report = pack([v for f in fingers for v in ((f[0], 1), (f[1], 1), (f[2], 6), (f[3], 8), (f[4], 16), (f[5], 16))]
              + [(0x1234, 16), (2, 8), (1, 1), (0, 7)])
check("finger positions", [(hid_get_value(report, xs[i]), hid_get_value(report, ys[i])) for i in range(2)],
      [(1000, 2000), (3000, 100)])
check("contact count", hid_get_value(report, count_field), 2)
check("an unsigned maximum written as a byte", parse(UsagePage(1) + LogMin(0) + item(1, 2, 0xFF, 1) + Size(8)
                                                      + Count(1) + Usage(0x30) + Input(VAR))[1].fields[0].logical_max, 255)

# --- malformed and limits ------------------------------------------------------------------------
check("truncated item", parse(b"\x05")[0], -EINVAL)
check("truncated 4-byte item", parse(b"\x07\x01\x02")[0], -EINVAL)
check("end collection with none open", parse(End)[0], -EINVAL)
check("report ID 0", parse(ReportID(0))[0], -EINVAL)
check("elements over 32 bits", parse(Size(33) + Count(1) + Input(VAR))[0], -EINVAL)
check("a report over the limit", parse(Size(32) + Count(2000) + Input(VAR))[0], -EINVAL)
check("Pop with nothing pushed", parse(Pop(0))[0], -EINVAL)
check("Push too deep", parse(Push(0) * 5)[0], -ENOSPC)
check("too many fields", parse(Size(1) + Count(1) + Input(VAR) * 257)[0], -ENOSPC)
check("too many usages", parse(Usage(1) * 1025)[0], -ENOSPC)
check("too many collections", parse((Collection_(LOGICAL) + End) * 65)[0], -ENOSPC)
check("nesting too deep", parse(Collection_(LOGICAL) * 17)[0], -ENOSPC)
check("long items are skipped", parse(b"\xFE\x02\x10\xAA\xBB" + mouse)[0], 0)
check("a long item past the end", parse(b"\xFE\x05\x10\xAA")[0], -EINVAL)
check("collections left open are tolerated", parse(Collection_(APPLICATION))[0], 0)
check("empty descriptor", parse(b"")[0], 0)
rng = random.Random(7)
for _ in range(5000):
    b = bytearray(touchpad if rng.random() < 0.6 else rng.randbytes(rng.randint(1, 200)))
    for _ in range(rng.randint(1, 10)):
        b[rng.randrange(len(b))] = rng.getrandbits(8)
    st, d = parse(b)
    if st == 0:
        for f in fields(d)[:8]:
            hid_get_value(bytes(64), f, 0)
check("5000 mutated descriptors parse and read without a crash", True, True)

print(f"test_hid: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

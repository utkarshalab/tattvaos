"""AML start-up tests: _REG, the _STA/_INI walk, device IDs.

usage: python3 test_init.py path/to/aml.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403

lib = C.CDLL(sys.argv[1])


class Value(C.Structure):
    _fields_ = [("type", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint16),
                ("len", C.c_uint32), ("data", C.c_uint64)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


aml_init = fn("aml_init", C.c_int32, C.c_void_p, C.c_uint64)
aml_load = fn("aml_load", C.c_int32, C.c_char_p)
aml_find = fn("aml_find", C.c_void_p, C.c_char_p)
aml_eval_path = fn("aml_eval_path", C.c_int32, C.c_char_p, C.c_void_p, C.c_uint32, C.POINTER(Value))
aml_initialize = fn("aml_initialize", C.c_int32)
aml_status = fn("aml_device_status", C.c_int32, C.c_void_p)
aml_match = fn("aml_match_id", C.c_int32, C.c_void_p, C.c_char_p)
aml_find_device = fn("aml_find_device", C.c_void_p, C.c_char_p, C.c_uint32)
aml_run_reg = fn("aml_run_reg", C.c_int32, C.c_uint32)
counter = lambda n: C.c_uint32.in_dll(lib, n).value  # noqa: E731

HEAP_SIZE = 1 << 20
_heap = C.create_string_buffer(HEAP_SIZE + 16)
HEAP = (C.addressof(_heap) + 15) & ~15
tables = []


def fresh():
    tables.clear()
    assert aml_init(HEAP, HEAP_SIZE) == 0


def load(*terms):
    t = C.create_string_buffer(Table(*terms))
    tables.append(t)
    return aml_load(t)


def val(path):
    out = Value()
    st = aml_eval_path(path.encode(), None, 0, C.byref(out))
    if st:
        return ("error", -st)
    if out.type == 1:
        return out.data
    if out.type == 4:
        arr = (Value * out.len).from_address(out.data)
        return [e.data for e in arr]
    return ("type", out.type)


def node(path):
    return aml_find(path.encode())


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


SB = BS + "_SB"


def eisa(text):
    """EISAID("PNP0C50") as the integer ASL produces."""
    c = [ord(x) - 0x40 for x in text[:3]]
    v = (c[0] << 26 | c[1] << 21 | c[2] << 16 | int(text[3:], 16))
    return struct.unpack("<I", struct.pack(">I", v))[0]


def order(tag):
    """_INI shifts a tag into the integer ORDR, one byte per call."""
    return Method("_INI", 0, Store(Or(ShiftLeft(N(BS + "ORDR"), Int(8)), Int(tag)), N(BS + "ORDR")))


# --- the walk ----------------------------------------------------------------------
fresh()
check("load", load(
    Name("ORDR", Zero),
    Scope(SB,
          order(0x10),                                      # \_SB._INI runs first
          Device("DEVA", order(0x01),
                 Device("CHA1", order(0x02))),
          Device("DEVB", Method("_STA", 0, Return(Zero)), order(0x03),
                 Device("CHB1", order(0x04))),              # skipped: parent absent
          Device("DEVC", Method("_STA", 0, Return(Int(0x08))), order(0x05),
                 Device("CHC1", order(0x06))),              # functional, not present:
                                                            # no _INI, children walked
          Device("DEVD", Name("_STA", Int(0x0F)), order(0x07)),
          Device("DEVE", Method("_STA", 0, Return(N("NOPE")))),    # _STA fails: absent
          Device("DEVF", Method("_INI", 0, Return(N("NOPE")))),    # _INI fails
          Device("DEVG", order(0x08)),
          Processor("CPU0", 0, order(0x09)),
          ThermalZone("TZ00", order(0x0A))),
), 0)
check("initialize", aml_initialize(), 0)
got = [b for b in val("ORDR").to_bytes(8, "big") if b]
check("_INI order: \\_SB first, depth first, skipping absent devices",
      got, [0x10, 0x01, 0x02, 0x06, 0x07, 0x08, 0x09, 0x0A])
check("devices seen (\\_SB is a scope)", counter("aml_init_devices"), 11)
check("_INI methods run, the failing one too", counter("aml_init_inis"), 9)
check("failures counted", counter("aml_init_errors"), 2)
check("status without _STA", aml_status(node(SB + ".DEVA")), 0x0F)
check("status from a _STA method", aml_status(node(SB + ".DEVB")), 0)
check("functional only", aml_status(node(SB + ".DEVC")), 0x08)
check("status from a _STA name", aml_status(node(SB + ".DEVD")), 0x0F)
check("failed _STA reads as absent", aml_status(node(SB + ".DEVE")), 0)
check("child of an absent device never evaluated", aml_status(node(SB + ".DEVB.CHB1")), -1)
check("the walk can run again", (aml_initialize(), counter("aml_init_inis")), (0, 9))

# --- IDs ----------------------------------------------------------------------------
fresh()
check("load ids", load(
    Scope(SB,
          Device("TPD0", Name("_HID", Str("MSFT0001")), Name("_CID", Int(eisa("PNP0C50")))),
          Device("TPD1", Name("_HID", Int(eisa("PNP0C50")))),
          Device("TPD2", Method("_HID", 0, Return(Str("ACPI0C50"))),
                 Name("_CID", Pkg(Str("XYZ0001"), Int(eisa("PNP0C50"))))),
          Device("TPD3", Name("_HID", Int(eisa("PNP0C50"))), Name("_STA", Zero)),
          Device("LID0", Name("_HID", Int(eisa("PNP0C0D")))),
          Device("NOID"))),
    0)
aml_initialize()
check("EISA _HID", aml_match(node(SB + ".TPD1"), b"PNP0C50"), 1)
check("string _HID", aml_match(node(SB + ".TPD0"), b"MSFT0001"), 1)
check("EISA _CID", aml_match(node(SB + ".TPD0"), b"PNP0C50"), 1)
check("_HID method", aml_match(node(SB + ".TPD2"), b"ACPI0C50"), 1)
check("_CID package", aml_match(node(SB + ".TPD2"), b"PNP0C50"), 1)
check("no match", aml_match(node(SB + ".LID0"), b"PNP0C50"), 0)
check("prefix is not a match", aml_match(node(SB + ".TPD1"), b"PNP0C5"), 0)
check("no ID at all", aml_match(node(SB + ".NOID"), b"PNP0C50"), 0)
found = [aml_find_device(b"PNP0C50", i) for i in range(4)]
check("present devices with an ID, in order",
      found, [node(SB + ".TPD0"), node(SB + ".TPD1"), node(SB + ".TPD2"), None])
check("lid", aml_find_device(b"PNP0C0D", 0), node(SB + ".LID0"))

# --- _REG ---------------------------------------------------------------------------
fresh()
check("load reg", load(
    Name("REGS", Zero),
    Scope(SB,
          Device("EC0",
                 OpRegion("ECR0", 3, 0, 0x100), OpRegion("ECR1", 3, 0x80, 0x10),
                 Name("ECON", Zero),
                 Method("_REG", 2, If(LEqual(Arg(0), Int(3)), Store(Arg(1), N("ECON"))),
                        Increment(N(BS + "REGS")))),
          Device("PCI0", OpRegion("CFG0", 2, 0, 0x100),
                 Method("_REG", 2, Increment(N(BS + "REGS")))),
          Device("NOR0", OpRegion("ECR2", 3, 0, 4)))),            # no _REG: fine
    0)
check("_REG for the embedded controller space", aml_run_reg(3), 0)
check("_REG told the space is connected", val(SB + ".EC0.ECON"), 1)
check("_REG once per device", val("REGS"), 1)
check("_REG for another space", (aml_run_reg(2), val("REGS")), (0, 2))
check("no region in a space: nothing called", (aml_run_reg(7), val("REGS")), (0, 2))

print(f"test_init: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

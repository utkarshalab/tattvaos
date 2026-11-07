"""_DSM tests.

usage: python3 test_dsm.py path/to/aml.so
"""
import ctypes as C
import os
import sys
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403

lib = C.CDLL(sys.argv[1])
ENOTFOUND = 3


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
aml_dsm = fn("aml_dsm", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32, C.POINTER(Value))
aml_dsm_supported = fn("aml_dsm_supported", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32)


def touuid(text):
    """ToUUID byte order: the first three groups little-endian."""
    return uuid.UUID(text).bytes_le


HID = touuid("3CDFF6F7-4267-4555-AD05-B30A3D8938DE")      # I2C-HID descriptor address
OTHER = touuid("12345678-1234-1234-1234-123456789ABC")

heap = C.create_string_buffer((1 << 20) + 16)
assert aml_init((C.addressof(heap) + 15) & ~15, 1 << 20) == 0
SB = BS + "_SB"
table = C.create_string_buffer(Table(Scope(SB,
    Device("TPD0",
           Method("_DSM", 4,
                  If(LEqual(Arg(0), Buf(HID)),
                     If(LEqual(Arg(2), Zero),
                        If(LEqual(Arg(1), One), Return(Buf([0x03]))),
                        Return(Buf([0x00]))),
                     If(LEqual(Arg(2), One), Return(Int(0x20)))),
                  Return(Buf([0x00])))),
    Device("INT0",                                          # function 0 as an integer
           Method("_DSM", 4, If(LEqual(Arg(2), Zero), Return(Int(0x05))), Return(Int(0x99)))),
    Device("NONE"),
    Device("BIG0",                                          # functions past the first byte
           Method("_DSM", 4, If(LEqual(Arg(2), Zero), Return(Buf([0x01, 0x02]))), Return(One))))))
assert aml_load(table) == 0

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def node(name):
    return aml_find((SB + "." + name).encode())


v = Value()
check("descriptor address", (aml_dsm(node("TPD0"), HID, 1, 1, C.byref(v)), v.type, v.data), (0, 1, 0x20))
check("function 1 supported", aml_dsm_supported(node("TPD0"), HID, 1, 1), 1)
check("function 2 not supported", aml_dsm_supported(node("TPD0"), HID, 1, 2), 0)
check("another revision supports nothing", aml_dsm_supported(node("TPD0"), HID, 2, 1), 0)
check("another UUID supports nothing", aml_dsm_supported(node("TPD0"), OTHER, 1, 1), 0)
check("function 0 as an integer", (aml_dsm_supported(node("INT0"), HID, 1, 2),
                                   aml_dsm_supported(node("INT0"), HID, 1, 1)), (1, 0))
check("function in the second byte", (aml_dsm_supported(node("BIG0"), HID, 1, 9),
                                      aml_dsm_supported(node("BIG0"), HID, 1, 8)), (1, 0))
check("function past the buffer", aml_dsm_supported(node("BIG0"), HID, 1, 40), 0)
check("no _DSM", aml_dsm(node("NONE"), HID, 1, 0, C.byref(v)), -ENOTFOUND)
check("no _DSM: nothing supported", aml_dsm_supported(node("NONE"), HID, 1, 1), 0)

print(f"test_dsm: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

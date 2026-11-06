"""AML interpreter host tests.

usage: python3 test_aml.py path/to/aml.so
"""
import ctypes as C
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403
import aml_gen as G  # noqa: E402

lib = C.CDLL(sys.argv[1])

EBADCODE, ENOMEM, ENOTFOUND, ETYPE, EUNSUPPORTED, EBUDGET, EINDEX, EDIVZERO, EFATAL, EEXISTS, EARGS = range(1, 12)
T_INT, T_STR, T_BUF, T_PKG, T_FIELD, T_DEVICE = 1, 2, 3, 4, 5, 6
T_METHOD, T_MUTEX, T_REGION, T_REF, T_NAMEREF = 8, 9, 10, 0x21, 0x23
REF_NODE = 2
ONES64 = (1 << 64) - 1


class Value(C.Structure):
    _fields_ = [("type", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint16),
                ("len", C.c_uint32), ("data", C.c_uint64)]


assert C.sizeof(Value) == 16


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


aml_init = fn("aml_init", C.c_int32, C.c_void_p, C.c_uint64)
aml_load = fn("aml_load", C.c_int32, C.c_char_p)
aml_find = fn("aml_find", C.c_void_p, C.c_char_p)
aml_eval_path = fn("aml_eval_path", C.c_int32, C.c_char_p, C.c_void_p, C.c_uint32, C.POINTER(Value))
heap_used = fn("aml_heap_used", C.c_uint64)

REGION = C.CFUNCTYPE(C.c_int32, C.c_uint64, C.c_uint64, C.c_uint32, C.c_uint32, C.POINTER(C.c_uint64))
NOTIFY = C.CFUNCTYPE(None, C.c_void_p, C.c_uint64)
hook_region = C.c_void_p.in_dll(lib, "aml_region_fn")
hook_notify = C.c_void_p.in_dll(lib, "aml_notify_fn")
dup_names = C.c_uint32.in_dll(lib, "aml_dup_names")

HEAP_SIZE = 1 << 20
_heap = C.create_string_buffer(HEAP_SIZE + 16)
HEAP = (C.addressof(_heap) + 15) & ~15
tables = []         # loaded tables must stay alive: methods point into them

# simulated address spaces: (space, address) -> byte
memory = {}
accesses = []


def region(space, addr, width, write, ptr):
    nbytes = width // 8
    accesses.append((space, addr, width, write))
    if space not in (0, 1):
        return -EUNSUPPORTED
    if write:
        v = ptr[0]
        for i in range(nbytes):
            memory[(space, addr + i)] = (v >> (8 * i)) & 0xFF
    else:
        v = 0
        for i in range(nbytes):
            v |= memory.get((space, addr + i), 0) << (8 * i)
        ptr[0] = v
    return 0


region_cb = REGION(region)
notified = []
notify_cb = NOTIFY(lambda node, v: notified.append((node, v)))


def fresh(size=HEAP_SIZE):
    memory.clear()
    accesses.clear()
    notified.clear()
    tables.clear()
    hook_region.value = C.cast(region_cb, C.c_void_p).value
    hook_notify.value = C.cast(notify_cb, C.c_void_p).value
    assert aml_init(HEAP, size) == 0


def load(*terms, revision=2, sig="DSDT"):
    t = C.create_string_buffer(Table(*terms, revision=revision, sig=sig))
    tables.append(t)
    return aml_load(t)


def arg_values(args):
    vals = (Value * 7)()
    keep = []
    for i, a in enumerate(args):
        if isinstance(a, int):
            vals[i].type, vals[i].data = T_INT, a
        elif isinstance(a, (bytes, str)):
            b = a.encode() if isinstance(a, str) else a
            buf = C.create_string_buffer(b)
            keep.append(buf)
            vals[i].type = T_STR if isinstance(a, str) else T_BUF
            vals[i].len, vals[i].data = len(b), C.addressof(buf)
    return vals, keep


def ev(path, *args):
    out = Value()
    vals, keep = arg_values(args)
    st = aml_eval_path(path.encode(), C.cast(vals, C.c_void_p), len(args), C.byref(out))
    return st, out


def py(v):
    """A value as Python data."""
    if v.type == T_INT:
        return v.data
    if v.type == T_STR:
        return C.string_at(v.data, v.len).decode()
    if v.type == T_BUF:
        return C.string_at(v.data, v.len)
    if v.type == T_PKG:
        arr = (Value * v.len).from_address(v.data)
        return [py(e) for e in arr]
    if v.type == T_REF:
        return ("ref", v.sub, v.data)
    return ("type", v.type)


def val(path, *args):
    st, v = ev(path, *args)
    if st != 0:
        return ("error", -st)
    return py(v)


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


SB = BS + "_SB"

# --- data objects and names ------------------------------------------------------------
fresh()
check("load", load(
    Name("INT1", Int(0x1234)), Name("BIG1", Int(0x123456789A)), Name("ZER1", Zero),
    Name("ONE1", One), Name("ALL1", Ones),
    Name("STR1", Str("hello")), Name("BUF1", Buf([1, 2, 3, 4])), Name("BUF2", Buf([7], size=4)),
    Name("PKG1", Pkg(One, Str("a"), Pkg(Int(5)))),
    Scope(SB, Device("DEV0", Name("_HID", Int(0x0C0CD041)),
                     Method("_STA", 0, Return(Int(0x0F)))))), 0)
check("integer", val("INT1"), 0x1234)
check("qword", val("BIG1"), 0x123456789A)
check("zero one ones", (val("ZER1"), val("ONE1"), val("ALL1")), (0, 1, ONES64))
check("string", val("STR1"), "hello")
check("buffer", val("BUF1"), b"\x01\x02\x03\x04")
check("buffer padded to its size", val("BUF2"), b"\x07\x00\x00\x00")
check("package", val("PKG1"), [1, "a", [5]])
check("device name", val(SB + ".DEV0._HID"), 0x0C0CD041)
check("method", val(SB + ".DEV0._STA"), 0x0F)
check("short path text", val(BS + "_SB.DEV0._STA"), 0x0F)
check("missing name", val("NOPE"), ("error", ENOTFOUND))
check("device object", val(SB + ".DEV0")[0], "type")
check("predefined _REV", val("_REV"), 2)
check("predefined _OS", val("_OS"), "Utkarsha OS")
check("_OSI feature", val("_OSI", "Module Device"), ONES64)
check("_OSI unknown", val("_OSI", "Something Else"), 0)
check("_OSI prefix only", val("_OSI", "Module"), 0)

# --- methods, arguments, locals, control flow ---------------------------------------------
fresh()
check("load methods", load(
    Method("ADD2", 2, Return(Add(Arg(0), Arg(1)))),
    Method("SUM1", 1,
           Store(Zero, Local(0)), Store(Zero, Local(1)),
           While(LLess(Local(1), Arg(0)),
                 Increment(Local(1)),
                 Add(Local(0), Local(1), Local(0))),
           Return(Local(0))),
    Method("EVEN", 1,                       # sum of even numbers below Arg0, with Continue/Break
           Store(Zero, Local(0)), Store(Zero, Local(1)),
           While(One,
                 If(LGreaterEqual(Local(1), Arg(0)), Break),
                 Increment(Local(1)),
                 If(And(Local(1), One), Continue),
                 Add(Local(0), Local(1), Local(0))),
           Return(Local(0))),
    Method("SIGN", 1,
           If(LLess(Arg(0), Int(10)), Return(Str("small"))),
           Else(If(LEqual(Arg(0), Int(10)), Return(Str("ten"))),
                Else(Return(Str("big"))))),
    Method("NONE", 0, Noop),
    Method("CALL", 0, Return(Call("ADD2", Int(40), Int(2)))),
    Method("FWD1", 0, Return(Call("LATE", Int(3)))),
    Method("LATE", 1, Return(Multiply(Arg(0), Int(7)))),
    Method("REC1", 0, Return(Call("REC1"))),
    Method("LOOP", 0, While(One, Noop)),
    Method("DIV0", 0, Return(Divide(One, Zero))),
    Method("DIVM", 0,
           Divide(Int(47), Int(5), Local(0), Local(1)),
           Return(Pkg(Local(0), Local(1)))),
    Method("MTH1", 0, Return(Pkg(Mod(Int(47), Int(5)), ShiftLeft(One, Int(4)), ShiftRight(Int(0x80), Int(3)),
                                 And(Int(0xF0), Int(0x3C)), Or(Int(0xF0), Int(0x0F)), XOr(Int(0xFF), Int(0x0F)),
                                 Subtract(Int(10), Int(3)), FindSetLeftBit(Int(0x80)), FindSetRightBit(Int(0x80)),
                                 FindSetLeftBit(Zero), NAnd(Ones, Ones), NOr(Zero, Zero)))),
    Method("NOTB", 0, Return(Not(Zero))),
    Method("DEC1", 0, Store(Int(5), Local(0)), Decrement(Local(0)), Return(Local(0))),
    Method("LOGI", 0, Return(Pkg(LAnd(One, Int(2)), LAnd(One, Zero), LOr(Zero, Zero), LOr(Zero, Int(9)),
                                 LNot(Zero), LNot(Int(3)), LNotEqual(One, Int(2)), LLessEqual(Int(2), Int(2)),
                                 LGreater(Int(3), Int(2)), LGreaterEqual(One, Int(2))))),
    Method("STRC", 0, Return(Pkg(LEqual(Str("abc"), Str("abc")), LLess(Str("abc"), Str("abd")),
                                 LGreater(Str("abcd"), Str("abc")), LEqual(Buf([1, 2]), Buf([1, 2])),
                                 LEqual(Int(16), Str("10"))))),
    Method("FTL1", 0, Fatal()),
    Method("MAT1", 0, Return(Match())),
), 0)
check("arguments", val("ADD2", 2, 3), 5)
check("too few arguments", val("ADD2", 2), ("error", EARGS))
check("while loop", val("SUM1", 10), 55)
check("break and continue", val("EVEN", 10), 2 + 4 + 6 + 8 + 10)
check("if", val("SIGN", 3), "small")
check("else if", val("SIGN", 10), "ten")
check("else", val("SIGN", 11), "big")
check("no return gives 0", val("NONE"), 0)
check("method call", val("CALL"), 42)
check("call to a method defined later", val("FWD1"), 21)
check("recursion stops", val("REC1"), ("error", EBUDGET))
check("endless loop stops", val("LOOP"), ("error", EBUDGET))
check("divide by zero", val("DIV0"), ("error", EDIVZERO))
check("divide remainder and quotient", val("DIVM"), [2, 9])
check("arithmetic", val("MTH1"), [2, 16, 0x10, 0x30, 0xFF, 0xF0, 7, 8, 8, 0, 0, ONES64])
check("not", val("NOTB"), ONES64)
check("decrement", val("DEC1"), 4)
check("logic", val("LOGI"), [ONES64, 0, 0, ONES64, ONES64, 0, ONES64, ONES64, ONES64, 0])
check("comparisons of strings and buffers", val("STRC"), [ONES64, ONES64, ONES64, ONES64, ONES64])
check("fatal", val("FTL1"), ("error", EFATAL))
check("unsupported opcode", val("MAT1"), ("error", EUNSUPPORTED))
check("interpreter still works after errors", val("ADD2", 1, 1), 2)

# --- store, conversions, objects ---------------------------------------------------------
fresh()
check("load store", load(
    Name("NINT", Zero), Name("NSTR", Str("old")), Name("NBUF", Buf([0, 0, 0, 0])),
    Name("NPKG", Pkg(One, Int(2), Int(3))),
    Method("ST1", 0, Store(Str("1F"), N("NINT")), Return(N("NINT"))),
    Method("ST2", 0, Store(Int(0x0201), N("NBUF")), Return(N("NBUF"))),
    Method("ST3", 0, Store(Str("new"), N("NSTR")), Return(N("NSTR"))),
    Method("ST4", 0, Store(Int(99), Index(N("NPKG"), One)), Return(DerefOf(Index(N("NPKG"), One)))),
    Method("ST5", 0, Store(Int(0xAB), Index(N("NBUF"), Int(3))), Return(N("NBUF"))),
    Method("SZ1", 0, Return(Pkg(SizeOf(N("NSTR")), SizeOf(N("NBUF")), SizeOf(N("NPKG"))))),
    Method("TI1", 0, Return(Pkg(ToInteger(Str("0x1F")), ToInteger(Str("123")), ToInteger(Buf([1, 2]))))),
    Method("TB1", 0, Return(ToBuffer(Str("ab")))),
    Method("TS1", 0, Return(ToString(Buf(b"hi\x00zz")))),
    Method("MID1", 0, Return(Pkg(Mid(Str("abcdef"), Int(2), Int(3)), Mid(Str("abc"), Int(2), Int(10))))),
    Method("CAT1", 0, Return(Pkg(Concatenate(Str("ab"), Str("cd")), Concatenate(Buf([1]), Buf([2, 3])),
                                 Concatenate(Int(1), Int(2))))),
    Method("OT1", 0, Return(Pkg(ObjectType(N("NINT")), ObjectType(N("NSTR")), ObjectType(N("ST1")),
                                ObjectType(N(SB)), ObjectType(Local(0))))),
    Method("CR1", 0, Return(Pkg(CondRefOf(N("NINT")), CondRefOf(N("NOPE"))))),
    Method("CR2", 0, CondRefOf(N("NINT"), Local(0)), Return(DerefOf(Local(0)))),
    Method("RF1", 1, Store(Int(77), Arg(0))),
    Method("RF2", 0, Store(Zero, N("NINT")), Call("RF1", RefOf(N("NINT"))), Return(N("NINT"))),
    Method("CP1", 0, CopyObject(Str("now a string"), N("NINT")), Return(N("NINT"))),
    Method("LCP", 0, Store(N("NBUF"), Local(0)), Store(Int(0x55), Index(Local(0), Zero)), Return(N("NBUF"))),
    Method("MTX", 0, Acquire("MX01"), Release("MX01"), Return(One)),
    Mutex("MX01"),
    Method("DBG1", 0, Store(Str("to debug"), Debug), Return(One)),
    Method("IDX9", 0, Return(Index(N("NPKG"), Int(9)))),
), 0)
check("store converts to the integer's type", val("ST1"), 0x1F)
check("store converts to the buffer's type, keeps its size", val("ST2"), b"\x01\x02\x00\x00")
check("store a string", val("ST3"), "new")
check("store into a package element", val("ST4"), 99)
check("store into a buffer byte", val("ST5"), b"\x01\x02\x00\xAB")
check("sizeof", val("SZ1"), [3, 4, 3])
check("ToInteger", val("TI1"), [0x1F, 123, 0x0201])
check("ToBuffer of a string", val("TB1"), b"ab\x00")
check("ToString stops at NUL", val("TS1"), "hi")
check("Mid", val("MID1"), ["cde", "c"])
check("Concatenate", val("CAT1"), ["abcd", b"\x01\x02\x03", struct.pack("<QQ", 1, 2)])
check("ObjectType", val("OT1"), [T_INT, T_STR, T_METHOD, T_DEVICE, 0])
check("CondRefOf", val("CR1"), [ONES64, 0])
check("CondRefOf target and DerefOf", val("CR2"), 0x1F)
check("store through a reference argument", val("RF2"), 77)
check("CopyObject changes the type", val("CP1"), "now a string")
check("a local is a copy, not the named buffer", val("LCP"), b"\x01\x02\x00\xAB")
check("mutex acquire and release", val("MTX"), 1)
check("store to Debug", val("DBG1"), 1)
check("index past the end", val("IDX9"), ("error", EINDEX))

# --- buffer fields -------------------------------------------------------------------------------
fresh()
check("load buffer fields", load(
    Name("RBUF", Buf([0] * 12)),
    CreateDWordField(N("RBUF"), Int(4), "RDW0"),
    CreateWordField(N("RBUF"), Int(8), "RW00"),
    CreateByteField(N("RBUF"), Int(10), "RB00"),
    CreateBitField(N("RBUF"), Int(88), "RBIT"),
    CreateField(N("RBUF"), Int(3), Int(5), "RF05"),
    Method("BF1", 0,
           Store(Int(0x11223344), N("RDW0")), Store(Int(0xBEEF), N("RW00")),
           Store(Int(0x7F), N("RB00")), Store(One, N("RBIT")), Store(Int(0x1F), N("RF05")),
           Return(N("RBUF"))),
    Method("BF2", 0, Return(Pkg(N("RDW0"), N("RW00"), N("RB00"), N("RBIT"), N("RF05")))),
    Method("BF3", 0, Store(Pkg(Zero, Zero, Zero, Zero, Zero), Local(0)),
           Store(N("RDW0"), Index(Local(0), Zero)), Store(N("RW00"), Index(Local(0), One)),
           Store(N("RB00"), Index(Local(0), Int(2))), Store(N("RBIT"), Index(Local(0), Int(3))),
           Store(N("RF05"), Index(Local(0), Int(4))), Return(Local(0))),
    Method("CRS1", 0,                        # the usual _CRS pattern, in a method
           Name("TBUF", Buf([0] * 8)),
           CreateDWordField(N("TBUF"), Zero, "TMIN"),
           CreateDWordField(N("TBUF"), Int(4), "TMAX"),
           Store(Int(0x1000), N("TMIN")), Store(Int(0x1FFF), N("TMAX")),
           Return(N("TBUF"))),
    Method("LBF1", 0,
           Store(Buf([0] * 4), Local(0)),
           CreateWordField(Local(0), One, "LW00"),
           Store(Int(0xA55A), N("LW00")),
           Return(Local(0))),
    Method("BADF", 0, CreateDWordField(N("RBUF"), Int(10), "OVER")),
), 0)
check("buffer field writes", val("BF1"), bytes([0xF8, 0, 0, 0, 0x44, 0x33, 0x22, 0x11, 0xEF, 0xBE, 0x7F, 0x01]))
check("buffer field reads", val("BF3"), [0x11223344, 0xBEEF, 0x7F, 1, 0x1F])
check("names in a package are references", [e[0] for e in val("BF2")], ["ref"] * 5)
check("fields in a method", val("CRS1"), struct.pack("<II", 0x1000, 0x1FFF))
check("method names are temporary: second call works", val("CRS1"), struct.pack("<II", 0x1000, 0x1FFF))
check("no duplicates from repeated calls", dup_names.value, 0)
check("method's names are gone after it returns", aml_find(b"CRS1.TBUF"), None)
check("buffer field on a local", val("LBF1"), b"\x00\x5A\xA5\x00")
check("buffer field past the end", val("BADF"), ("error", EINDEX))

# --- region fields ---------------------------------------------------------------------------------
fresh()
check("load region fields", load(
    OpRegion("MEM0", 0, 0x1000, 0x10),
    Field("MEM0", DWORD | PRESERVE, F("FA", 8), F("FB", 4), Reserved(4), F("FC", 16), F("FD", 32)),
    Field("MEM0", BYTE | ONES, Reserved(64), F("FE", 4)),
    Field("MEM0", ANY, Reserved(96), F("FF", 16)),
    OpRegion("IO00", 1, 0x70, 2),
    Field("IO00", BYTE, F("IDX0", 8), F("DAT0", 8)),
    IndexField("IDX0", "DAT0", BYTE, Reserved(16), F("CM02", 8), F("CM03", 8)),
    OpRegion("BNK0", 0, 0x2000, 4),
    Field("BNK0", BYTE, F("BSEL", 8)),
    BankField("BNK0", "BSEL", Int(2), BYTE, Reserved(8), F("BK01", 8)),
    Method("RG1", 0, Store(Int(0xAB), N("FA")), Store(Int(0x5), N("FB")), Store(Int(0x1234), N("FC")),
           Store(Int(0xCAFEF00D), N("FD")), Store(Pkg(Zero, Zero, Zero, Zero), Local(0)),
           Store(N("FA"), Index(Local(0), Zero)), Store(N("FB"), Index(Local(0), One)),
           Store(N("FC"), Index(Local(0), Int(2))), Store(N("FD"), Index(Local(0), Int(3))),
           Return(Local(0))),
    Method("RG2", 0, Store(Int(0x3), N("FE")), Return(N("FE"))),
    Method("RG3", 0, Store(Int(0xBEEF), N("FF")), Return(N("FF"))),
    Method("IX1", 0, Store(Int(0x42), N("CM03")), Return(N("CM03"))),
    Method("BK1", 0, Store(Int(0x99), N("BK01")), Return(N("BK01"))),
    OpRegion("PCI0", 2, 0, 0x100),
    Field("PCI0", DWORD, F("PCIV", 32)),
    Method("PC1", 0, Return(N("PCIV"))),
    OpRegion("TINY", 0, 0x3000, 1),
    Field("TINY", DWORD, F("TOOB", 32)),
    Method("OOB1", 0, Return(N("TOOB"))),
), 0)
check("region fields", val("RG1"), [0xAB, 0x5, 0x1234, 0xCAFEF00D])
check("region bytes", [memory.get((0, 0x1000 + i), 0) for i in range(8)],
      [0xAB, 0x05, 0x34, 0x12, 0x0D, 0xF0, 0xFE, 0xCA])
check("dword access width", all(w == 32 for (s, a, w, wr) in accesses if s == 0 and a < 0x1008), True)
accesses.clear()
check("write-as-ones field", val("RG2"), 0x3)
check("write-as-ones other bits", memory.get((0, 0x1008)), 0xF3)
check("write-as-ones does not read first", [a for a in accesses if a[3] == 0 and a[1] == 0x1008][:1],
      [(0, 0x1008, 8, 0)])      # only the read back by RG2's Return
accesses.clear()
check("any access picks one word", val("RG3"), 0xBEEF)
check("any access width", sorted({w for (_s, _a, w, _wr) in accesses}), [16])
check("index field", val("IX1"), 0x42)
check("index register written", memory.get((1, 0x70)), 3)
check("data register holds the value", memory.get((1, 0x71)), 0x42)
check("bank field", val("BK1"), 0x99)
check("bank selected", memory.get((0, 0x2000)), 2)
check("unsupported region space", val("PC1"), ("error", EUNSUPPORTED))
check("field outside its region", val("OOB1"), ("error", EINDEX))
hook_region.value = None
check("no region handler", val("RG2"), ("error", EUNSUPPORTED))

# --- notify, alias, external, scope, processor ------------------------------------------------------
fresh()
check("load misc", load(
    Scope(SB, Device("PCI0", Device("LPC0", Name("_ADR", Int(0x1F0000)))),
          Processor("CPU0", 0),
          ThermalZone("TZ00", Name("_TMP", Int(3000)))),
    Alias(SB + ".PCI0.LPC0", "LPCA"),
    External("EXT1", T_METHOD, 1),
    Method("XC1", 0, Return(Call("EXT1", Int(5)))),
    Method("NT1", 0, Notify(N(SB + ".PCI0"), Int(0x80)), Return(One)),
    Scope(SB + ".PCI0.LPC0", Method("UP01", 0, Return(N("^^LPC0._ADR"))),
          Method("UP02", 0, Return(N("^_ADR")))),
    Method("SRC1", 0, Return(N("_ADR"))),
    Scope(SB + ".PCI0", Method("SRC2", 0, Return(N("^LPC0._ADR"))),
          Method("SRC3", 0, Return(N("LPC0._ADR"))),
          Method("SRC4", 0, Return(N("_ADR")))),
    Scope(SB + ".PCI0.LPC0", Method("SRC5", 0, Return(N("_ADR")))),
    Name("INT1", One), Name("INT1", Int(2)),
    Scope("UNDC", Name("X000", Int(5))),
), 0)
check("alias", val("LPCA._ADR"), 0x1F0000)
check("external not yet defined", val("XC1"), ("error", ENOTFOUND))
check("ssdt defines the external", load(Method("EXT1", 1, Return(Add(Arg(0), One))), sig="SSDT"), 0)
check("external call after the ssdt", val("XC1"), 6)
check("notify", (val("NT1"), [v for (_n, v) in notified]), (1, [0x80]))
check("notify gets the node", notified[0][0], aml_find((SB + ".PCI0").encode()))
# a method opens a scope: ^ inside it is the device holding the method
check("two parent prefixes in a method", val(SB + ".PCI0.LPC0.UP01"), 0x1F0000)
check("one parent prefix in a method", val(SB + ".PCI0.LPC0.UP02"), 0x1F0000)
check("search stops at the root", val("SRC1"), ("error", ENOTFOUND))
check("relative path through a parent prefix", val(SB + ".PCI0.SRC2"), 0x1F0000)
check("multi-segment relative path is relative to the method", val(SB + ".PCI0.SRC3"), ("error", ENOTFOUND))
check("single name searches upward, not down", val(SB + ".PCI0.SRC4"), ("error", ENOTFOUND))
check("single name found in the enclosing device", val(SB + ".PCI0.LPC0.SRC5"), 0x1F0000)
check("processor", val(SB + ".CPU0")[0], "type")
check("thermal zone", val(SB + ".TZ00._TMP"), 3000)
check("duplicate name skipped, first kept", (val("INT1"), dup_names.value), (1, 1))
check("scope that was never declared", val("UNDC.X000"), 5)

# --- integer width: revision 1 tables use 32 bits ----------------------------------------------------
fresh()
check("load rev 1", load(Name("ONE2", Ones), Method("WRAP", 0, Return(Add(Int(0xFFFFFFFF), Int(2)))),
                         revision=1), 0)
check("32-bit ones", val("ONE2"), 0xFFFFFFFF)
check("32-bit wrap", val("WRAP"), 1)

# --- packages with names ----------------------------------------------------------------------------
fresh()
check("load package names", load(
    Scope(SB, Device("LNKA", Name("_UID", One))),
    Name("PRT0", Pkg(Pkg(Int(0xFFFF), Zero, N(SB + ".LNKA"), Zero),
                     Pkg(Int(0xFFFF), One, N("LNKZ"), Zero))),
    Method("PR1", 0, Return(ObjectType(DerefOf(Index(DerefOf(Index(N("PRT0"), Zero)), Int(2)))))),
), 0)
p = val("PRT0")
check("package name element is a reference", (p[0][2][0], p[0][2][1], p[0][2][2]),
      ("ref", REF_NODE, aml_find((SB + ".LNKA").encode())))
check("unresolved name element", p[1][2], ("type", T_NAMEREF))
check("_PRT walk", val("PR1"), T_DEVICE)

# --- malformed input and limits -----------------------------------------------------------------------
fresh()
good = Table(Name("AAAA", One), Method("BBBB", 1, If(Arg(0), Return(Str("x"))), Return(Buf([1, 2, 3]))),
             Device("CCCC", Name("_HID", Str("ABC0001"))))
for cut in range(37, len(good)):
    t = bytearray(good[:cut])
    t[4:8] = struct.pack("<I", cut)
    fresh()
    buf = C.create_string_buffer(bytes(t))
    st = aml_load(buf)
    if st not in (0, -EBADCODE, -ENOTFOUND, -ETYPE, -EUNSUPPORTED):
        check(f"truncated at {cut}", st, "a clean error")
check("every truncation ends cleanly", True, True)

fresh()
check("header too short", aml_load(C.create_string_buffer(b"DSDT" + struct.pack("<I", 10) + b"\x00" * 28)),
      -EBADCODE)

fresh(size=4096)
check("tiny heap", load(*[Name("N%03d" % i, Int(i)) for i in range(200)]), -ENOMEM)

rng = random.Random(1234)
crashes = 0
for i in range(3000):
    t = bytearray(good)
    for _ in range(rng.randint(1, 6)):
        t[rng.randint(36, len(t) - 1)] = rng.randint(0, 255)
    fresh()
    buf = C.create_string_buffer(bytes(t))
    st = aml_load(buf)
    for path in (b"AAAA", b"BBBB", b"CCCC._HID"):
        out = Value()
        aml_eval_path(path, None, 0, C.byref(out))
check("3000 mutated tables load and evaluate without crashing", True, True)

print(f"test_aml: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

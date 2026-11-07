"""Batteries, the AC adapter and thermal zones (power.asm).

The library is kstub.asm. Firmware is a DSDT built with aml_gen.py; Notify
goes through the event service the way an SCI-run method's would.

usage: python3 test_power.py path/to/kstub.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403

lib = C.CDLL(sys.argv[1])
UNKNOWN = 0xFFFFFFFF
POWER_BATTERY, POWER_AC, POWER_THERMAL = 1, 2, 3


class Value(C.Structure):
    _fields_ = [("type", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint16),
                ("len", C.c_uint32), ("data", C.c_uint64)]


class Battery(C.Structure):
    _fields_ = [("node", C.c_uint64), ("present", C.c_uint32), ("unit", C.c_uint32),
                ("design", C.c_uint32), ("full", C.c_uint32), ("design_mv", C.c_uint32),
                ("warning", C.c_uint32), ("low", C.c_uint32), ("technology", C.c_uint32),
                ("cycles", C.c_uint32), ("state", C.c_uint32), ("rate", C.c_uint32),
                ("remaining", C.c_uint32), ("voltage", C.c_uint32), ("percent", C.c_uint32),
                ("model", C.c_char * 24), ("serial", C.c_char * 24), ("kind", C.c_char * 24),
                ("oem", C.c_char * 24)]


class Thermal(C.Structure):
    _fields_ = [("node", C.c_uint64), ("temp", C.c_int32), ("critical", C.c_int32),
                ("hot", C.c_int32), ("passive", C.c_int32), ("over", C.c_uint32), ("pad", C.c_uint32)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


acpi_kernel_init = fn("acpi_kernel_init", None)
service = fn("acpi_events_service", C.c_int32)
aml_eval_path = fn("aml_eval_path", C.c_int32, C.c_char_p, C.c_void_p, C.c_uint32, C.POINTER(Value))
aml_load = fn("aml_load", C.c_int32, C.c_void_p)
aml_find = fn("aml_find", C.c_void_p, C.c_char_p)
battery_info = fn("acpi_battery_info", C.c_void_p, C.c_uint32)
thermal_info = fn("acpi_thermal_info", C.c_void_p, C.c_uint32)
ac_state = fn("acpi_ac_state", C.c_int32)
power_notify = fn("acpi_power_notify", C.c_int32, C.c_void_p, C.c_uint64)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731
C.c_uint64.from_address(C.addressof(C.c_uint8.in_dll(lib, "phys_state")) + 72).value = 1 << 47

keep = []
HEAP = C.create_string_buffer((2 << 20) + 16)
changes = []
POWER_FN = C.CFUNCTYPE(None, C.c_uint32, C.c_uint32)
power_cb = POWER_FN(lambda what, which: changes.append((what, which)))


def mem(data):
    b = C.create_string_buffer(bytes(data), max(len(data), 1))
    keep.append(b)
    return C.addressof(b)


def header(sig, body, revision=2):
    t = bytearray(sig.encode() + struct.pack("<IBB", 36 + len(body), revision, 0) + b"TESTID" + b"TESTTBL "
                  + struct.pack("<I", 1) + b"TEST" + struct.pack("<I", 1) + body)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


def console():
    n = u32("kstub_out_len").value
    return C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n).decode(errors="replace")


def boot(dsdt_body):
    dsdt = mem(header("DSDT", dsdt_body))
    f = bytearray(244 - 36)
    struct.pack_into("<Q", f, 140 - 36, dsdt)
    fadt = mem(header("FACP", bytes(f), revision=6))
    xsdt = mem(header("XSDT", struct.pack("<Q", fadt)))
    rsdp = bytearray(b"RSD PTR " + b"\x00" + b"TESTID" + b"\x02" + struct.pack("<I", 0) + struct.pack("<I", 36)
                     + struct.pack("<Q", xsdt) + b"\x00\x00\x00\x00")
    rsdp[8] = (-sum(rsdp[:20])) & 0xFF
    rsdp[32] = (-sum(rsdp[:36])) & 0xFF
    info = bytearray(112)
    struct.pack_into("<Q", info, 24, mem(rsdp))
    C.c_uint64.in_dll(lib, "boot_info_ptr").value = mem(info)
    C.c_uint64.in_dll(lib, "kstub_pages").value = (C.addressof(HEAP) + 15) & ~15
    u32("kstub_out_len").value = 0
    changes.clear()
    C.c_void_p.in_dll(lib, "acpi_power_fn").value = None
    acpi_kernel_init()
    C.c_void_p.in_dll(lib, "acpi_power_fn").value = C.cast(power_cb, C.c_void_p).value


def run(text):
    """Load a method body as a new table and run it; Notify then goes
    through the event service. Each gets its own name: a table cannot
    define one that is already there."""
    name = "TR%02d" % len(keep)
    t = C.create_string_buffer(Table(Method(name, 0, *text)))
    keep.append(t)
    aml_load(t)
    v = Value()
    aml_eval_path(name.encode(), None, 0, C.byref(v))
    service()


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


SB = BS + "_SB"
EISA = lambda t: struct.unpack("<I", struct.pack(">I", ((ord(t[0]) - 64) << 26) | ((ord(t[1]) - 64) << 21)  # noqa: E731
                                                  | ((ord(t[2]) - 64) << 16) | int(t[3:], 16)))[0]
K = lambda c: Int(int(round(c * 10)) + 2732)   # noqa: E731  degrees C to tenths of a kelvin

BIX = Pkg(Zero, Zero, Int(50000), Int(45000), One, Int(11400), Int(2250), Int(450), Int(123),
          Int(95000), Int(UNKNOWN), Int(UNKNOWN), Int(UNKNOWN), Int(UNKNOWN),
          Int(1), Int(1), Str("BIF0573"), Str("12345"), Str("LION"), Str("MSI Corp."))
BIF = Pkg(One, Int(4000), Int(3800), One, Int(11100), Int(400), Int(100), One, One,
          Str("SMALL"), Str("S1"), Str("LiP"), Str("ACME"))
DSDT = b"".join([
    Scope(SB,
          Name("ACST", One), Name("BST0", Zero), Name("REM0", Int(22500)), Name("RAT0", Int(9000)),
          Name("REM1", Int(1900)), Name("BSTA", Int(0x1F)), Name("TMPV", K(45.5)),
          Name("PBST", Pkg(Zero, Zero, Zero, Zero)),
          Device("BAT0", Name("_HID", Int(EISA("PNP0C0A"))),
                 Method("_STA", 0, Return(N(SB + ".BSTA"))),
                 Method("_BIX", 0, Return(BIX)),
                 Method("_BIF", 0, Return(BIF)),
                 Method("_BST", 0,
                        Store(N(SB + ".BST0"), Index(N(SB + ".PBST"), Zero)),
                        Store(N(SB + ".RAT0"), Index(N(SB + ".PBST"), One)),
                        Store(N(SB + ".REM0"), Index(N(SB + ".PBST"), Int(2))),
                        Store(Int(11800), Index(N(SB + ".PBST"), Int(3))),
                        Return(N(SB + ".PBST")))),
          Device("BAT1", Name("_HID", Int(EISA("PNP0C0A"))), Name("_UID", One),
                 Method("_BIF", 0, Return(BIF)),
                 Method("_BST", 0, Return(Pkg(Int(2), Int(500), N(SB + ".REM1"), Int(11000))))),
          Device("ADP1", Name("_HID", Str("ACPI0003")),
                 Method("_PSR", 0, Return(N(SB + ".ACST")))),
          ThermalZone("TZ0",
                      Method("_TMP", 0, Return(N(SB + ".TMPV"))),
                      Method("_CRT", 0, Return(K(100))),
                      Method("_PSV", 0, Return(K(85))))),
])

boot(DSDT)
check("found", (u32("acpi_battery_count").value, u32("acpi_thermal_count").value, ac_state()), (2, 1, 1))
b = Battery.from_address(battery_info(0))
check("_BIX: capacities, units, voltage, levels",
      (b.present, b.unit, b.design, b.full, b.technology, b.design_mv, b.warning, b.low),
      (1, 0, 50000, 45000, 1, 11400, 2250, 450))
check("_BIX: cycle count and strings",
      (b.cycles, b.model, b.serial, b.kind, b.oem), (123, b"BIF0573", b"12345", b"LION", b"MSI Corp."))
check("_BST through a package filled by Index", (b.state, b.rate, b.remaining, b.voltage, b.percent),
      (0, 9000, 22500, 11800, 50))
b1 = Battery.from_address(battery_info(1))
check("_BIF only: the older layout", (b1.unit, b1.design, b1.full, b1.cycles, b1.model, b1.oem),
      (1, 4000, 3800, UNKNOWN, b"SMALL", b"ACME"))
check("no _STA: present; _BST with a name in the package", (b1.present, b1.state, b1.remaining, b1.percent),
      (1, 2, 1900, 50))
check("no third battery", battery_info(2), None)
t = Thermal.from_address(thermal_info(0))
check("thermal: _TMP, _CRT, _PSV, no _HOT", (t.temp, t.critical, t.passive, t.hot & 0xFFFFFFFF, t.over),
      (455, 1000, 850, UNKNOWN, 0))
out = console()
check("console", ["ACPI: battery 0: 50%" + chr(13) in out, "ACPI: battery 1: 50%, charging" in out,
                  "ACPI: AC adapter online" in out, "ACPI: thermal zone 0: 45 C (critical 100 C)" in out],
      [True] * 4)

# Notify: battery state, unplugging, information
run([Store(Int(1), N(SB + ".BST0")), Store(Int(9000), N(SB + ".REM0")), Notify(N(SB + ".BAT0"), Int(0x80))])
b = Battery.from_address(battery_info(0))
check("Notify 0x80: state again", (b.state, b.remaining, b.percent, changes), (1, 9000, 20, [(POWER_BATTERY, 0)]))
changes.clear()
run([Store(Zero, N(SB + ".ACST")), Notify(N(SB + ".ADP1"), Int(0x80))])
check("the adapter goes", (ac_state(), changes), (0, [(POWER_AC, 0)]))
changes.clear()
run([Store(Int(0x0F), N(SB + ".BSTA")), Notify(N(SB + ".BAT0"), Int(0x81))])
b = Battery.from_address(battery_info(0))
check("taken out", (b.present, b.percent, changes), (0, UNKNOWN, [(POWER_BATTERY, 0)]))
changes.clear()

# thermal
run([Store(K(70), N(SB + ".TMPV")), Notify(N(SB + ".TZ0"), Int(0x80))])
t = Thermal.from_address(thermal_info(0))
check("a warmer zone", (t.temp, t.over, changes, u32("acpi_thermal_critical_count").value),
      (700, 0, [(POWER_THERMAL, 0)], 0))
changes.clear()
u32("kstub_out_len").value = 0
run([Store(K(101), N(SB + ".TMPV")), Notify(N(SB + ".TZ0"), Int(0x80))])
t = Thermal.from_address(thermal_info(0))
check("critical: flagged, counted and said",
      (t.temp, t.over, u32("acpi_thermal_critical_count").value, "AT OR OVER ITS CRITICAL" in console()),
      (1010, 1, 1, True))
changes.clear()
run([Store(Int(2732 - 50), N(SB + ".TMPV")), Notify(N(SB + ".TZ0"), Int(0x80))])
t = Thermal.from_address(thermal_info(0))
check("below zero", t.temp, -50)
check("other devices are not ours", power_notify(aml_find((SB + ".ACST").encode()), 0x80), 0)
before = u32("acpi_notifies").value
run([Notify(N(SB + ".ADP1"), Int(0x80))])
check("theirs do not count as unhandled", u32("acpi_notifies").value, before)

# a desktop: none of them
boot(Scope(SB, Device("XXXX", Name("_HID", Str("ABCD0001")))))
check("none", (u32("acpi_battery_count").value, u32("acpi_thermal_count").value, ac_state(),
               battery_info(0), thermal_info(0), "battery" in console()), (0, 0, -1, None, None, False))

print(f"test_power: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

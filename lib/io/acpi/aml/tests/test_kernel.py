"""Kernel glue tests: table discovery, start-up, the region sandbox.

The library is kstub.asm: kernel.asm with the few kernel symbols it uses
stubbed out (console output is captured).

usage: python3 test_kernel.py path/to/kstub.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403

lib = C.CDLL(sys.argv[1])
EUNSUPPORTED, EDENIED = 5, 12


class Value(C.Structure):
    _fields_ = [("type", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint16),
                ("len", C.c_uint32), ("data", C.c_uint64)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


acpi_kernel_init = fn("acpi_kernel_init", None)
aml_eval_path = fn("aml_eval_path", C.c_int32, C.c_char_p, C.c_void_p, C.c_uint32, C.POINTER(Value))
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731
u64 = lambda n: C.c_uint64.in_dll(lib, n)  # noqa: E731
boot_info_ptr = u64("boot_info_ptr")
kstub_pages = u64("kstub_pages")
out_len = u32("kstub_out_len")
delays = u64("kstub_delays")
kernel_image = C.addressof(C.c_uint8.in_dll(lib, "kernel_text_start"))
# phys_state.direct_map_limit is at offset 72 (the tenth qword)
phys_state = C.addressof(C.c_uint8.in_dll(lib, "phys_state"))
C.c_uint64.from_address(phys_state + 72).value = 1 << 47

keep = []


def mem(data, size=None):
    b = C.create_string_buffer(bytes(data), size or max(len(data), 1))
    keep.append(b)
    return C.addressof(b)


HEAP = C.create_string_buffer((2 << 20) + 16)
HEAP_ADDR = (C.addressof(HEAP) + 15) & ~15


def output():
    s = C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), out_len.value).decode()
    out_len.value = 0
    return s


def header(sig, body, revision=2):
    t = bytearray(sig.encode() + struct.pack("<IBB", 36 + len(body), revision, 0) + b"TESTID" + b"TESTTBL "
                  + struct.pack("<I", 1) + b"TEST" + struct.pack("<I", 1) + body)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


def firmware(dsdt, ssdts=(), rsdp_ok=True, bad_dsdt_checksum=False, e820=()):
    """Tables in memory and a boot-info block pointing at them."""
    if bad_dsdt_checksum:
        dsdt = bytearray(dsdt)
        dsdt[9] ^= 0x55
        dsdt = bytes(dsdt)
    dsdt_addr = mem(dsdt)
    fadt_body = bytearray(244 - 36)
    struct.pack_into("<I", fadt_body, 40 - 36, 0)                  # 32-bit DSDT unused
    struct.pack_into("<Q", fadt_body, 140 - 36, dsdt_addr)          # X_DSDT
    fadt_addr = mem(header("FACP", bytes(fadt_body), revision=6))
    entries = [fadt_addr] + [mem(s) for s in ssdts]
    xsdt_addr = mem(header("XSDT", b"".join(struct.pack("<Q", e) for e in entries)))
    rsdp = bytearray(b"RSD PTR " + b"\x00" + b"TESTID" + b"\x02" + struct.pack("<I", 0)
                     + struct.pack("<I", 36) + struct.pack("<Q", xsdt_addr) + b"\x00\x00\x00\x00")
    rsdp[8] = (-sum(rsdp[:20])) & 0xFF
    rsdp[32] = (-sum(rsdp[:36])) & 0xFF
    if not rsdp_ok:
        rsdp[0:8] = b"RSD PTX "
    rsdp_addr = mem(rsdp)
    e820_addr = mem(b"".join(struct.pack("<QQII", base, length, t, 0) for (base, length, t) in e820) or b"\x00")
    info = bytearray(112)
    struct.pack_into("<QI", info, 0, e820_addr, len(e820))
    struct.pack_into("<Q", info, 24, rsdp_addr)
    boot_info_ptr.value = mem(info)
    kstub_pages.value = HEAP_ADDR


def ev(path):
    out = Value()
    st = aml_eval_path(path.encode(), None, 0, C.byref(out))
    return ("error", -st) if st else (out.data if out.type == 1 else ("type", out.type))


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


SB = BS + "_SB"
EISA_PNP0C50, EISA_PNP0C0D = 0x500CD041, 0x0D0CD041

# --- a working machine -----------------------------------------------------------------
mmio = C.create_string_buffer(64)
C.memmove(mmio, struct.pack("<I", 0x12345678), 4)
ram = C.create_string_buffer(64)
MMIO, RAM = C.addressof(mmio), C.addressof(ram)
dsdt = header("DSDT", b"".join([
    Scope(SB,
          Device("TPD0", Name("_HID", Int(EISA_PNP0C50))),
          Device("LID0", Name("_HID", Int(EISA_PNP0C0D)),
                 Method("_INI", 0, Notify(N(SB + ".LID0"), Int(0x80)), Sleep(Int(5))))),
    OpRegion("MMIO", 0, MMIO, 16), Field("MMIO", DWORD, F("REG0", 32), F("REG1", 32)),
    OpRegion("RAM0", 0, RAM, 16), Field("RAM0", DWORD, F("RAMF", 32)),
    OpRegion("KERN", 0, kernel_image, 16), Field("KERN", BYTE, F("KRNF", 8)),
    OpRegion("PCIP", 1, 0xCF8, 8), Field("PCIP", DWORD, F("PCIA", 32)),
    OpRegion("WIDE", 1, 0x80, 8), Field("WIDE", QWORD, F("WIDF", 64)),
    OpRegion("HIGH", 1, 0xFFFE, 4), Field("HIGH", DWORD, F("HIGF", 32)),
    OpRegion("ECSP", 3, 0, 16), Field("ECSP", BYTE, F("ECF0", 8)),
    Method("WR1", 0, Store(Int(0xCAFE), N("REG1")), Return(N("REG1"))),
]))
ssdt = header("SSDT", Method("FROM", 0, Return(Int(77))))
firmware(dsdt, [ssdt], e820=[(RAM, 64, 1), (MMIO, 64, 2)])
acpi_kernel_init()
log = output()
check("ready", u32("acpi_ready").value, 1)
check("DSDT loaded", ("ACPI: DSDT %d bytes loaded" % len(dsdt)) in log, True)
check("SSDT loaded", ("ACPI: SSDT %d bytes loaded" % len(ssdt)) in log, True)
check("SSDT method", ev("FROM"), 77)
check("summary", "ACPI: devices 2, _INI run 1, failures 0" in log, True)
check("present devices", "ACPI: present: PNP0C50 PNP0C0D \r\n" in log, True)
check("Notify printed", "ACPI: Notify LID0 value 0000000000000080" in log, True)
check("Sleep reaches udelay", delays.value, 5001)
check("memory region read", ev("REG0"), 0x12345678)
check("memory region write", (ev("WR1"), struct.unpack_from("<I", mmio.raw, 4)[0]), (0xCAFE, 0xCAFE))
check("usable RAM refused", ev("RAMF"), ("error", EDENIED))
check("first refusal printed once", output().count("ACPI: sandbox refused space 0 address"), 1)
check("kernel image refused", ev("KRNF"), ("error", EDENIED))
check("PCI configuration ports refused", ev("PCIA"), ("error", EDENIED))
check("64-bit port access refused", ev("WIDF"), ("error", EUNSUPPORTED))
check("ports past 0xFFFF refused", ev("HIGF"), ("error", EDENIED))
check("embedded controller space not yet", ev("ECF0"), ("error", EUNSUPPORTED))
check("refusals counted", u32("acpi_denied").value, 4)
check("no message after the first refusal", "sandbox refused" in output(), False)

# --- firmware problems -----------------------------------------------------------------------
firmware(dsdt, bad_dsdt_checksum=True)
acpi_kernel_init()
log = output()
check("bad checksum: used anyway", (u32("acpi_ready").value, "bad checksum used anyway: DSDT" in log), (1, True))

firmware(dsdt, rsdp_ok=False)
acpi_kernel_init()
check("no RSDP", (u32("acpi_ready").value, "ACPI: no valid RSDP" in output()), (0, True))

broken = header("DSDT", Name("AAAA", One) + b"\x14\x30")         # a Method cut short
firmware(broken)
acpi_kernel_init()
log = output()
check("a table that fails to load is reported", "stopped with error -1 at offset 000000000000002C" in log, True)
check("and the boot goes on", u32("acpi_ready").value, 1)

firmware(dsdt)
kstub_pages.value = 0                                              # no memory
acpi_kernel_init()
check("no memory", (u32("acpi_ready").value, "no memory for the interpreter" in output()), (0, True))

print(f"test_kernel: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

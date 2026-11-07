"""The ACPI lid and buttons as input devices (kernel_acpi.asm).

usage: python3 test_acpi_input.py path/to/tp.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "io", "acpi", "aml", "tests"))
import aml_gen as A  # noqa: E402

lib = C.CDLL(sys.argv[1])
KEY, SWITCH = 1, 9
KEY_POWER, KEY_SLEEP = 116, 142


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


acpi_kernel_init = fn("acpi_kernel_init", None)
input_acpi_init = fn("input_acpi_init", None)
input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
dev_info = fn("ut_input_device_info", C.c_int64, C.c_uint32)
notify = fn("acpi_events_notify", None, C.c_void_p, C.c_uint64)
service = fn("acpi_events_service", C.c_int32)
aml_find = fn("aml_find", C.c_void_p, C.c_char_p)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731

C.c_uint64.from_address(C.addressof(C.c_uint8.in_dll(lib, "phys_state")) + 72).value = 1 << 47
NOOP_OFF = C.CFUNCTYPE(C.c_uint64)(lambda: 0)
NOOP_RESTORE = C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)
C.c_void_p.in_dll(lib, "input_irq_off_fn").value = C.cast(NOOP_OFF, C.c_void_p).value
C.c_void_p.in_dll(lib, "input_irq_restore_fn").value = C.cast(NOOP_RESTORE, C.c_void_p).value


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class DevInfo(C.Structure):
    _fields_ = [("id", C.c_uint32), ("pad0", C.c_uint32), ("name", C.c_char_p), ("bus", C.c_uint32),
                ("vendor", C.c_uint16), ("product", C.c_uint16), ("version", C.c_uint16),
                ("pad1", C.c_uint16 * 3), ("caps", C.c_uint64)]


events = []
on_event = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)(
    lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                Event.from_address(e).value, Event.from_address(e).device)))
keep = []
HEAP = C.create_string_buffer((2 << 20) + 16)


def mem(data):
    b = C.create_string_buffer(bytes(data), max(len(data), 1))
    keep.append(b)
    return C.addressof(b)


def header(sig, body, revision=2):
    t = bytearray(sig.encode() + struct.pack("<IBB", 36 + len(body), revision, 0) + b"TESTID" + b"TESTTBL "
                  + struct.pack("<I", 1) + b"TEST" + struct.pack("<I", 1) + body)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


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
    input_init()
    events.clear()
    register(C.cast(on_event, C.c_void_p), 0)
    C.c_void_p.in_dll(lib, "acpi_lid_fn").value = None
    C.c_void_p.in_dll(lib, "acpi_button_fn").value = None
    acpi_kernel_init()
    input_acpi_init()
    pump()


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


SB = A.BS + "_SB"
LID = struct.unpack("<I", struct.pack(">I", (16 << 26) | (14 << 21) | (16 << 16) | 0x0C0D))[0]   # PNP0C0D
boot(A.Scope(SB, A.Name("LIDS", A.Zero),
             A.Device("LID0", A.Name("_HID", A.Int(LID)), A.Method("_LID", 0, A.Return(A.N(SB + ".LIDS"))))))
lid_dev, btn_dev = u32("iac_lid_dev").value, u32("iac_button_dev").value
check("devices", (DevInfo.from_address(dev_info(lid_dev)).name, DevInfo.from_address(dev_info(lid_dev)).caps,
                  DevInfo.from_address(dev_info(btn_dev)).name), (b"ACPI lid", 16, b"ACPI buttons"))
check("the lid's state at start-up (closed)", events, [(SWITCH, 0, 1, lid_dev)])
events.clear()
lidnode = aml_find((SB + ".LID0").encode())
fns = {"lid": C.c_void_p.in_dll(lib, "acpi_lid_fn").value, "button": C.c_void_p.in_dll(lib, "acpi_button_fn").value}
check("hooks set", all(fns.values()), True)
store = A.Table(A.Method("OPEN", 0, A.Store(A.One, A.N(SB + ".LIDS"))))
t = C.create_string_buffer(store)
keep.append(t)
lib.aml_load(t)
v = (C.c_uint8 * 16)()
lib.aml_eval_path(b"OPEN", None, 0, v)
notify(lidnode, 0x80)
service()
pump()
check("the lid opens", events, [(SWITCH, 0, 0, lid_dev)])
events.clear()
C.CFUNCTYPE(None, C.c_uint32)(fns["button"])(1)
pump()
check("power button: a press and a release",
      events, [(KEY, KEY_POWER, 1, btn_dev), (KEY, KEY_POWER, 0, btn_dev)])
events.clear()
C.CFUNCTYPE(None, C.c_uint32)(fns["button"])(2)
pump()
check("sleep button", [e[1] for e in events], [KEY_SLEEP, KEY_SLEEP])
boot(A.Scope(SB, A.Device("XXXX", A.Name("_HID", A.Str("ABCD0001")))))
check("no lid: only the buttons", (u32("iac_lid_dev").value, u32("iac_button_dev").value != 0, events), (0, True, []))

print(f"test_acpi_input: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

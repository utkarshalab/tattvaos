"""ACPI events: ACPI mode, GPEs, fixed buttons, the embedded controller,
Notify to the lid and button hooks, storms.

The library is kstub.asm; its ports go to a simulated platform (PM1 and
GPE registers, an embedded controller, the SMI command port).

usage: python3 test_events.py path/to/kstub.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from aml_gen import *  # noqa: E402,F401,F403

lib = C.CDLL(sys.argv[1])
EBUDGET = 6


class Value(C.Structure):
    _fields_ = [("type", C.c_uint8), ("sub", C.c_uint8), ("pad", C.c_uint16),
                ("len", C.c_uint32), ("data", C.c_uint64)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


acpi_kernel_init = fn("acpi_kernel_init", None)
sci = fn("acpi_ev_sci_irq", C.c_int32)
service = fn("acpi_events_service", C.c_int32)
aml_eval_path = fn("aml_eval_path", C.c_int32, C.c_char_p, C.c_void_p, C.c_uint32, C.POINTER(Value))
ec_read = fn("acpi_ec_read", C.c_int32, C.c_uint32)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731
C.c_uint64.from_address(C.addressof(C.c_uint8.in_dll(lib, "phys_state")) + 72).value = 1 << 47

PM1_EVT, PM1_CNT, GPE0, SMI_CMD, ACPI_ENABLE = 0x400, 0x404, 0x420, 0xB2, 0xA0
EC_DATA, EC_CMD = 0x62, 0x66
PWRBTN = 1 << 8


class Platform:
    def __init__(self, sci_en=False):
        self.pm1_sts = 0
        self.pm1_en = 0
        self.pm1_cnt = 1 if sci_en else 0
        self.gpe_sts = [0] * 4
        self.gpe_en = [0] * 4
        self.writes = []
        # embedded controller
        self.ec = [0] * 256
        self.ec_out = []
        self.ec_state = None        # what the next data byte means
        self.ec_queries = []
        self.ec_stuck = False

    def gpe(self, n):
        self.gpe_sts[n // 8] |= 1 << (n % 8)

    def ec_status(self):
        v = 0
        if self.ec_out:
            v |= 1
        if self.ec_stuck:
            v |= 2
        if self.ec_queries:
            v |= 1 << 5
        return v

    def inp(self, port, width):
        if port == PM1_EVT:
            return self.pm1_sts
        if port == PM1_EVT + 2:
            return self.pm1_en
        if port == PM1_CNT:
            return self.pm1_cnt
        if GPE0 <= port < GPE0 + 4:
            return self.gpe_sts[port - GPE0]
        if GPE0 + 4 <= port < GPE0 + 8:
            return self.gpe_en[port - GPE0 - 4]
        if port == EC_CMD:
            return self.ec_status()
        if port == EC_DATA:
            return self.ec_out.pop(0) if self.ec_out else 0
        return 0xFF

    def out(self, port, width, v):
        self.writes.append((port, width, v))
        if port == PM1_EVT:
            self.pm1_sts &= ~v              # write 1 to clear
        elif port == PM1_EVT + 2:
            self.pm1_en = v
        elif port == SMI_CMD and v == ACPI_ENABLE:
            self.pm1_cnt |= 1
        elif GPE0 <= port < GPE0 + 4:
            self.gpe_sts[port - GPE0] &= ~v
        elif GPE0 + 4 <= port < GPE0 + 8:
            self.gpe_en[port - GPE0 - 4] = v & 0xFF
        elif port == EC_CMD:
            if v == 0x80:
                self.ec_state = "read-addr"
            elif v == 0x81:
                self.ec_state = "write-addr"
            elif v == 0x84:
                self.ec_out.append(self.ec_queries.pop(0) if self.ec_queries else 0)
        elif port == EC_DATA:
            if self.ec_state == "read-addr":
                self.ec_out.append(self.ec[v])
                self.ec_state = None
            elif self.ec_state == "write-addr":
                self.ec_addr = v
                self.ec_state = "write-data"
            elif self.ec_state == "write-data":
                self.ec[self.ec_addr] = v
                self.ec_state = None


plat = None
IN = C.CFUNCTYPE(C.c_uint32, C.c_uint32, C.c_uint32)
OUT = C.CFUNCTYPE(None, C.c_uint32, C.c_uint32, C.c_uint32)
in_cb = IN(lambda p, w: plat.inp(p, w))
out_cb = OUT(lambda p, w, v: plat.out(p, w, v))
C.c_void_p.in_dll(lib, "acpi_port_in_fn").value = C.cast(in_cb, C.c_void_p).value
C.c_void_p.in_dll(lib, "acpi_port_out_fn").value = C.cast(out_cb, C.c_void_p).value
lids, buttons = [], []
LID = C.CFUNCTYPE(None, C.c_uint32)
lid_cb = LID(lambda closed: lids.append(closed))
btn_cb = LID(lambda kind: buttons.append(kind))
now = [0]
CLOCK = C.CFUNCTYPE(C.c_uint64)
clock_cb = CLOCK(lambda: now[0])
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


def firmware(dsdt_body, flags=0):
    dsdt = mem(header("DSDT", dsdt_body))
    f = bytearray(244 - 36)

    def put(off, fmt, v):
        struct.pack_into(fmt, f, off - 36, v)
    put(46, "<H", 9)                    # SCI on IRQ 9
    put(48, "<I", SMI_CMD)
    put(52, "<B", ACPI_ENABLE)
    put(56, "<I", PM1_EVT)
    put(64, "<I", PM1_CNT)
    put(80, "<I", GPE0)
    put(88, "<B", 4)                    # PM1 event block: 2 status, 2 enable
    put(92, "<B", 8)                    # GPE0: 4 status, 4 enable bytes
    put(112, "<I", flags)
    put(140, "<Q", dsdt)
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


def IO(port):
    return bytes([0x47, 1]) + struct.pack("<HHBB", port, port, 1, 1)


SB = BS + "_SB"
EISA = lambda t: struct.unpack("<I", struct.pack(">I", ((ord(t[0]) - 64) << 26) | ((ord(t[1]) - 64) << 21)  # noqa: E731
                                                  | ((ord(t[2]) - 64) << 16) | int(t[3:], 16)))[0]
DSDT = b"".join([
    Name("FLAG", Zero), Name("RUNS", Zero),
    Scope(BS + "_GPE",
          Method("_L03", 0, Notify(N(SB + ".PWRB"), Int(0x80))),
          Method("_E05", 0, Store(One, N(BS + "FLAG")), Increment(N(BS + "RUNS")))),
    Scope(SB,
          Device("EC0", Name("_HID", Int(EISA("PNP0C09"))),
                 Name("_CRS", Buf(IO(EC_DATA) + IO(EC_CMD) + b"\x79\x00")),
                 Name("_GPE", Int(0x10)), Name("ECON", Zero),
                 OpRegion("ECOR", 3, 0, 0xFF),
                 Field("ECOR", BYTE, F("LIDS", 8), F("TEMP", 8)),
                 Method("_REG", 2, If(LEqual(Arg(0), Int(3)), Store(Arg(1), N("ECON")))),
                 Method("_Q42", 0, Notify(N(SB + ".LID0"), Int(0x80))),
                 Method("_Q43", 0, Notify(N(SB + ".THRM"), Int(0x81)))),
          Device("LID0", Name("_HID", Int(EISA("PNP0C0D"))), Method("_LID", 0, Return(N(SB + ".EC0.LIDS")))),
          Device("PWRB", Name("_HID", Int(EISA("PNP0C0C")))),
          Device("THRM", Name("_HID", Str("ABCD0001")))),
])


def boot(body=DSDT, sci_en=False, flags=0):
    global plat
    plat = Platform(sci_en)
    plat.ec[0] = 1                          # the lid is open
    plat.ec[1] = 42
    lids.clear()
    buttons.clear()
    firmware(body, flags)
    C.c_void_p.in_dll(lib, "acpi_lid_fn").value = C.cast(lid_cb, C.c_void_p).value
    C.c_void_p.in_dll(lib, "acpi_button_fn").value = C.cast(btn_cb, C.c_void_p).value
    acpi_kernel_init()
    C.c_void_p.in_dll(lib, "aml_clock_fn").value = C.cast(clock_cb, C.c_void_p).value
    n = u32("kstub_out_len")
    out = C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n.value).decode()
    n.value = 0
    return out


def val(path):
    v = Value()
    st = aml_eval_path(path.encode(), None, 0, C.byref(v))
    return ("error", -st) if st else v.data


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# --- start-up -------------------------------------------------------------------------------
log = boot()
check("embedded controller found", "ACPI: embedded controller, ports 0000000000000062, GPE 16" in log, True)
check("ACPI mode asked of the firmware", ((SMI_CMD, 8, ACPI_ENABLE) in plat.writes, plat.pm1_cnt & 1), (True, 1))
check("_REG told the firmware the EC works", val(SB + ".EC0.ECON"), 1)
check("EC fields read through the EC", (val(SB + ".EC0.LIDS"), val(SB + ".EC0.TEMP")), (1, 42))
check("GPEs with a method, and the EC's, enabled", (plat.gpe_en[0], plat.gpe_en[2]), (1 << 3 | 1 << 5, 1 << 0))
check("GPEs counted", u32("acpi_gpes_enabled").value, 3)
check("fixed power button enabled", plat.pm1_en & PWRBTN, PWRBTN)
check("events announced", "ACPI: events: SCI 9, GPEs enabled 3" in log, True)
route = (C.c_int32 * 3).in_dll(lib, "kstub_sci_route")
check("SCI routed", list(route), [9, 0x51, 0])
log = boot(sci_en=True)
check("already in ACPI mode: no SMI", any(w[0] == SMI_CMD for w in plat.writes), False)

# --- the fixed power button -----------------------------------------------------------------
plat.pm1_sts |= PWRBTN
check("SCI: one event", sci(), 1)
check("status cleared in the interrupt", plat.pm1_sts & PWRBTN, 0)
check("nothing reported before the fiber runs", buttons, [])
service()
check("power button reported", buttons, [1])

# --- a level GPE whose method notifies the power button -----------------------------------------
buttons.clear()
plat.gpe(3)
check("SCI: GPE 3", sci(), 1)
check("level GPE masked, status kept", (plat.gpe_en[0] & 8, plat.gpe_sts[0] & 8), (0, 8))
service()
check("_L03 ran: its Notify reached the button hook", buttons, [1])
check("level GPE cleared after the method, then enabled", (plat.gpe_sts[0] & 8, plat.gpe_en[0] & 8), (0, 8))

# --- an edge GPE ---------------------------------------------------------------------------------
plat.gpe(5)
sci()
check("edge GPE cleared in the interrupt", plat.gpe_sts[0] & 32, 0)
service()
check("_E05 ran", (val("FLAG"), u32("acpi_gpe_runs").value >= 2), (1, True))
check("edge GPE enabled again", plat.gpe_en[0] & 32, 32)

# --- the embedded controller's event: a query that notifies the lid -------------------------------
plat.ec[0] = 0                              # the lid closes
plat.ec_queries = [0x42, 0x43]
plat.gpe(16)
sci()
service()
check("both queries run", u32("acpi_ec_queries").value, 2)
check("_Q42's Notify: the lid hook with the lid's state (closed)", lids, [1])
n = u32("kstub_out_len")
out = C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n.value).decode()
n.value = 0
check("_Q43's Notify for another device is printed", "ACPI: Notify THRM value 0000000000000081" in out, True)
check("EC GPE enabled again", plat.gpe_en[2] & 1, 1)

# --- limits ---------------------------------------------------------------------------------------
for i in range(1001):
    plat.gpe(5)
    sci()
    service()
check("a GPE storm leaves it disabled", (u32("acpi_gpe_storms").value, plat.gpe_en[0] & 32), (1, 0))
plat.gpe(5)
check("disabled: the interrupt ignores it", sci(), 0)
now[0] = 5_000_000_000
for i in range(40):
    lib.acpi_events_notify(C.c_void_p(0x1000), C.c_uint64(1))
check("Notify queue overflow is counted", u32("acpi_notify_dropped").value, 8)
C.c_uint32.in_dll(lib, "acpi_notify_head").value = C.c_uint32.in_dll(lib, "acpi_notify_tail").value
plat.ec_stuck = True
check("a stuck EC fails the access, no hang", ec_read(0), -EBUDGET)
check("EC timeouts counted", u32("acpi_ec_timeouts").value >= 1, True)
plat.ec_stuck = False

# --- machines without these -------------------------------------------------------------------------
log = boot(flags=1 << 20)                   # hardware-reduced ACPI
check("hardware-reduced: no SCI", ("ACPI: events" in log, list(route)[0]), (False, 9))
log = boot(flags=1 << 4)                    # a control-method power button
check("control-method power button: the fixed one stays off", plat.pm1_en & PWRBTN, 0)
C.c_uint32.in_dll(lib, "kstub_sci_fail").value = 1
log = boot()
C.c_uint32.in_dll(lib, "kstub_sci_fail").value = 0
check("SCI routing refused is reported", "the SCI could not be routed" in log, True)
log = boot(b"".join([Name("FLAG", Zero), Scope(BS + "_GPE", Method("_E05", 0, Store(One, N(BS + "FLAG"))))]))
check("no EC: only the method GPE", (u32("acpi_ec_ready").value, u32("acpi_gpes_enabled").value), (0, 1))

print(f"test_events: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

"""The touchpad's kernel glue end to end, on the host.

Firmware tables describe a touchpad (I2C connection and GPIO interrupt),
its I2C controller and its GPIO controller as this laptop's firmware does.
Underneath: a simulated GPIO controller (sim_amd.py), a simulated
DesignWare I2C controller (sim_dw.py) and a simulated I2C-HID touchpad.

usage: python3 test_touchpad_kernel.py path/to/tp.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
for d in (HERE, os.path.join(ROOT, "lib/io/acpi/aml/tests"), os.path.join(ROOT, "lib/io/gpio/tests"),
          os.path.join(ROOT, "lib/io/i2c/tests")):
    sys.path.insert(0, d)
import aml_gen as A  # noqa: E402
from hid_gen import touchpad  # noqa: E402
from sim_amd import SimAMD, INT_DELIVER, LEVEL_TRIG, INT_ENABLE  # noqa: E402
from sim_dw import SimDW, FS_HCNT, FS_LCNT, SDA_HOLD, TAR  # noqa: E402
from sim_i2c_hid import SimI2cHid, DWAdapter, DESC_REG  # noqa: E402

lib = C.CDLL(sys.argv[1])
TOUCH, MOTION, BUTTON = 6, 2, 4


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


acpi_kernel_init = fn("acpi_kernel_init", None)
touchpad_init = fn("input_touchpad_init", None)
gpio_irq = fn("gpio_irq", C.c_int32, C.c_uint32)
service = fn("i2c_hid_service", C.c_int32)
input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
gpio_detach = fn("gpio_detach_all", None)
i2c_detach = fn("i2c_detach_all", None)
hid_reset = fn("i2c_hid_reset_all", None)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731

# --- the host stand-ins ---------------------------------------------------------------------
C.c_uint64.from_address(C.addressof(C.c_uint8.in_dll(lib, "phys_state")) + 72).value = 1 << 47
NOOP_OFF = C.CFUNCTYPE(C.c_uint64)(lambda: 0)
NOOP_RESTORE = C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)
C.c_void_p.in_dll(lib, "input_irq_off_fn").value = C.cast(NOOP_OFF, C.c_void_p).value
C.c_void_p.in_dll(lib, "input_irq_restore_fn").value = C.cast(NOOP_RESTORE, C.c_void_p).value
GPIO_BASE, I2C_BASE = 0x7E000000, 0x7D000000
sims = {}
RD = C.CFUNCTYPE(C.c_uint32, C.c_uint64)
WR = C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)


def mmio_rd(a):
    for base, (size, sim) in sims.items():
        if base <= a < base + size:
            return sim.read(a - base)
    raise AssertionError(hex(a))


def mmio_wr(a, v):
    for base, (size, sim) in sims.items():
        if base <= a < base + size:
            return sim.write(a - base, v)
    raise AssertionError(hex(a))


rd_cb, wr_cb = RD(mmio_rd), WR(mmio_wr)
for hook in ("gpio_read32_fn", "i2c_read32_fn"):
    C.c_void_p.in_dll(lib, hook).value = C.cast(rd_cb, C.c_void_p).value
for hook in ("gpio_write32_fn", "i2c_write32_fn"):
    C.c_void_p.in_dll(lib, hook).value = C.cast(wr_cb, C.c_void_p).value
# i2c_hid's transfer hook is set by the glue to i2c_write_read: the real path

events = []
EVCB = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


on_event = EVCB(lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                            Event.from_address(e).value)))
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


def firmware(dsdt_body):
    dsdt = mem(header("DSDT", dsdt_body))
    fadt = bytearray(244 - 36)
    struct.pack_into("<Q", fadt, 140 - 36, dsdt)
    fadt_addr = mem(header("FACP", bytes(fadt), revision=6))
    xsdt = mem(header("XSDT", struct.pack("<Q", fadt_addr)))
    rsdp = bytearray(b"RSD PTR " + b"\x00" + b"TESTID" + b"\x02" + struct.pack("<I", 0) + struct.pack("<I", 36)
                     + struct.pack("<Q", xsdt) + b"\x00\x00\x00\x00")
    rsdp[8] = (-sum(rsdp[:20])) & 0xFF
    rsdp[32] = (-sum(rsdp[:36])) & 0xFF
    info = bytearray(112)
    struct.pack_into("<Q", info, 24, mem(rsdp))
    C.c_uint64.in_dll(lib, "boot_info_ptr").value = mem(info)
    C.c_uint64.in_dll(lib, "kstub_pages").value = (C.addressof(HEAP) + 15) & ~15


# resource descriptors (byte layouts from the specification)
def large(t, data):
    return bytes([0x80 | t]) + struct.pack("<H", len(data)) + data


def Memory32Fixed(base, length):
    return large(6, struct.pack("<BII", 1, base, length))


def Interrupt(irq, level=True, low=True, shared=True):
    f = 1 | (0 if level else 2) | (4 if low else 0) | (8 if shared else 0)
    return large(9, struct.pack("<BBI", f, 1, irq))


def I2cBus(addr, speed, src):
    return large(14, struct.pack("<BBBBHBH", 2, 0, 1, 2, 0, 1, 6) + struct.pack("<IH", speed, addr)
                 + src.encode() + b"\x00")


def GpioInt(pin, src, edge=False, low=True):
    flags = (1 if edge else 0) | ((1 if low else 0) << 1) | 0x10
    name = src.encode() + b"\x00"
    return large(12, struct.pack("<BBHHBHHHBHHH", 1, 0, 0, flags, 1, 0, 0, 23, 0, 25, 0, 0)
                 + struct.pack("<H", pin) + name)


END = b"\x79\x00"
BS = A.BS
UUID = bytes([0xF7, 0xF6, 0xDF, 0x3C, 0x67, 0x42, 0x55, 0x45, 0xAD, 0x05, 0xB3, 0x0A, 0x3D, 0x89, 0x38, 0xDE])


def dsdt(touch_crs=None, dsm=True, gpio=True):
    if touch_crs is None:
        touch_crs = I2cBus(0x2C, 400000, BS + "_SB.I2CD") + GpioInt(9, BS + "_SB.GPIO") + END
    dev_body = [A.Name("_HID", A.Str("MSFT0001")), A.Name("_CID", A.Str("PNP0C50")),
                A.Name("_CRS", A.Buf(touch_crs))]
    if dsm:
        dev_body.append(A.Method("_DSM", 4,
                                 A.If(A.LEqual(A.Arg(0), A.Buf(UUID)),
                                      A.If(A.LEqual(A.Arg(2), A.Zero), A.Return(A.Buf([0x03]))),
                                      A.If(A.LEqual(A.Arg(2), A.One), A.Return(A.Int(DESC_REG)))),
                                 A.Return(A.Buf([0]))))
    parts = [A.Device("I2CD", A.Name("_HID", A.Str("AMDI0010")),
                      A.Name("_CRS", A.Buf(Memory32Fixed(I2C_BASE, 0x1000) + Interrupt(10) + END)),
                      A.Method("FMCN", 0, A.Return(A.Pkg(A.Int(0x55), A.Int(0x99), A.Int(0x1E))))),
             A.Device("TPD0", *dev_body)]
    if gpio:
        parts.insert(0, A.Device("GPIO", A.Name("_HID", A.Str("AMDI0030")),
                                 A.Name("_CRS", A.Buf(Memory32Fixed(GPIO_BASE, 0x400) + Interrupt(7) + END))))
    return A.Scope(BS + "_SB", *parts)


def output():
    n = u32("kstub_out_len")
    s = C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n.value).decode()
    n.value = 0
    return s


def boot(body):
    """Firmware, ACPI, the touchpad: like kernel_main does."""
    global gpio_sim, dw_sim, hid_dev
    gpio_detach()
    i2c_detach()
    hid_reset()
    input_init()
    events.clear()
    register(C.cast(on_event, C.c_void_p), 0)
    u32("tp_route_count").value = 0
    gpio_sim = SimAMD(GPIO_BASE, 190)
    dw_sim = SimDW()
    hid_dev = SimI2cHid(touchpad)
    dw_sim.devices[0x2C] = DWAdapter(hid_dev)
    sims.clear()
    sims[GPIO_BASE] = (0x400, gpio_sim)
    sims[I2C_BASE] = (0x1000, dw_sim)
    gpio_sim.inputs[9] = 1                  # the touchpad's line idles high
    firmware(body)
    acpi_kernel_init()
    touchpad_init()
    return output()


def routes():
    arr = (C.c_uint32 * 48).in_dll(lib, "tp_routes")
    return [tuple(arr[i * 3:i * 3 + 3]) for i in range(u32("tp_route_count").value)]


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# --- a working touchpad ----------------------------------------------------------------------
log = boot(dsdt())
check("ready", u32("itp_state").value, 1)
check("announced", "INPUT: I2C-HID touchpad at address 000000000000002C, GPIO pin 9" in log, True)
check("I2C timing from FMCN", (dw_sim.regs.get(FS_HCNT), dw_sim.regs.get(FS_LCNT), dw_sim.regs.get(SDA_HOLD)),
      (0x55, 0x99, 0x1E))
check("I2C target", dw_sim.regs.get(TAR), 0x2C)
check("touchpad reset and in multi-touch mode", (hid_dev.resets, hid_dev.features.get(3)), (1, b"\x03"))
r = gpio_sim.pin_reg(9)
check("pin 9: level, active low, enabled, delivered",
      (bool(r & LEVEL_TRIG), (r >> 9) & 3, bool(r & INT_ENABLE), bool(r & INT_DELIVER)), (True, 1, True, True))
check("GPIO interrupt routed masked, then unmasked, level and active low",
      routes(), [(7, 0x51, 1 | 2 | 4), (7, 0x51, 2 | 4)])
check("the handler installed at the vector", u32("kstub_idt_vector").value, 0x51)

# a finger: the line asserts, the controller interrupts, the fiber reads
rows = [(1, 1, 2, 1500, 900)] + [(0, 0, 0, 0, 0)] * 4
bits = [v for f in rows for v in ((f[0], 1), (f[1], 1), (0, 6), (f[2], 8), (f[3], 16), (f[4], 16))]
bits += [(0, 16), (1, 8), (0, 1), (0, 7)]
v, off = 0, 0
for value, size in bits:
    v |= (value & ((1 << size) - 1)) << off
    off += size
hid_dev.queue.append(b"\x01" + v.to_bytes(off // 8, "little"))
gpio_sim.drive(9, 0)
check("the GPIO interrupt reaches the touchpad's handler", gpio_irq(0), 1)
check("pin masked until the report is read", gpio_sim.pin_reg(9) & INT_DELIVER, 0)
gpio_sim.inputs[9] = 1                      # reading the report releases the line
check("the fiber reads the report", service(), 1)
pump()
check("a contact and a frame end", events,
      [(TOUCH, 2 | 1 << 12, 1500 | 900 << 16), (TOUCH, 3 << 8, 0)])
check("pin re-armed after the report", bool(gpio_sim.pin_reg(9) & INT_DELIVER), True)

# --- firmware that does not fit -------------------------------------------------------------
log = boot(A.Scope(BS + "_SB", A.Device("XXXX", A.Name("_HID", A.Str("ABCD0001")))))
check("no touchpad", (u32("itp_state").value, "no I2C-HID touchpad in ACPI" in log), (0, True))
log = boot(dsdt(touch_crs=I2cBus(0x2C, 400000, BS + "_SB.I2CD") + END))
check("no interrupt in _CRS", (u32("itp_state").value, "has no I2C connection or interrupt" in log), (0, True))
log = boot(dsdt(dsm=False))
check("no _DSM", (u32("itp_state").value, "_DSM gave no HID descriptor register" in log), (0, True))
log = boot(dsdt(touch_crs=I2cBus(0x2C, 400000, BS + "_SB.NONE") + GpioInt(9, BS + "_SB.GPIO") + END))
check("I2C controller missing", (u32("itp_state").value, "I2C controller not usable" in log), (0, True))
log = boot(dsdt(gpio=False))
check("GPIO controller missing", (u32("itp_state").value, "GPIO controller not usable" in log), (0, True))
u32("tp_route_fail").value = 1
log = boot(dsdt())
u32("tp_route_fail").value = 0
check("interrupt routing refused", (u32("itp_state").value, "could not be routed" in log), (0, True))
gpio_detach()
i2c_detach()
hid_reset()
input_init()
gpio_sim = SimAMD(GPIO_BASE, 190)
dw_sim = SimDW()
sims.clear()
sims[GPIO_BASE] = (0x400, gpio_sim)
sims[I2C_BASE] = (0x1000, dw_sim)
firmware(dsdt())
acpi_kernel_init()
output()
touchpad_init()                             # nobody on the bus at 0x2C
check("touchpad not answering", (u32("itp_state").value, "did not answer as I2C-HID, error -19" in output()),
      (0, True))

print(f"test_touchpad_kernel: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

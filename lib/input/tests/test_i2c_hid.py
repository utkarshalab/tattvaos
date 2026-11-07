"""I2C-HID tests: bring-up, multi-touch mode, touchpad and mouse reports.

A simulated I2C-HID device answers the driver's transfers through the
i2c_hid_xfer_fn hook.

usage: python3 test_i2c_hid.py path/to/input.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hid_gen import *  # noqa: E402,F401,F403
from sim_i2c_hid import SimI2cHid, DESC_REG  # noqa: E402

lib = C.CDLL(sys.argv[1])
EIO, ENXIO, ENODEV, EINVAL, ENOSPC = 5, 6, 19, 22, 28
TOUCH, MOTION, BUTTON, AXIS = 6, 2, 4, 5


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
dev_info = fn("ut_input_device_info", C.c_int64, C.c_uint32)
probe = fn("i2c_hid_probe", C.c_int32, C.c_uint32, C.c_uint32, C.c_uint32)
attention = fn("i2c_hid_attention", None, C.c_uint32)
service = fn("i2c_hid_service", C.c_int32)
set_after = fn("i2c_hid_set_after", None, C.c_uint32, C.c_void_p, C.c_uint64)
reset_all = fn("i2c_hid_reset_all", None)
counter = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class DevInfo(C.Structure):
    _fields_ = [("id", C.c_uint32), ("pad0", C.c_uint32), ("name", C.c_char_p), ("bus", C.c_uint32),
                ("vendor", C.c_uint16), ("product", C.c_uint16), ("version", C.c_uint16),
                ("pad1", C.c_uint16 * 3), ("caps", C.c_uint64), ("max_x", C.c_int32), ("max_y", C.c_int32),
                ("res_x", C.c_uint32), ("res_y", C.c_uint32), ("slots", C.c_uint32), ("pad2", C.c_uint32)]


# interrupts cannot be turned off in a host process: no-op hooks
NOOP_OFF = C.CFUNCTYPE(C.c_uint64)(lambda: 0)
NOOP_RESTORE = C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)
C.c_void_p.in_dll(lib, "input_irq_off_fn").value = C.cast(NOOP_OFF, C.c_void_p).value
C.c_void_p.in_dll(lib, "input_irq_restore_fn").value = C.cast(NOOP_RESTORE, C.c_void_p).value

events = []
EVCB = C.CFUNCTYPE(None, C.POINTER(Event), C.c_void_p)
on_event = EVCB(lambda e, c: events.append((e.contents.type, e.contents.code, e.contents.value)))


sim = None
XFER = C.CFUNCTYPE(C.c_int32, C.c_uint32, C.c_uint32, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32)


def do_xfer(ctrl, addr, wbuf, wlen, rbuf, rlen):
    w = C.string_at(wbuf, wlen) if wlen else b""
    st, data = sim.xfer(w, rlen)
    if rlen and st == 0:
        C.memmove(rbuf, data, rlen)
    return st


xfer_cb = XFER(do_xfer)
C.c_void_p.in_dll(lib, "i2c_hid_xfer_fn").value = C.cast(xfer_cb, C.c_void_p).value
delays = []
DELAY = C.CFUNCTYPE(None, C.c_uint64)
delay_cb = DELAY(lambda us: delays.append(us))
C.c_void_p.in_dll(lib, "i2c_hid_delay_fn").value = C.cast(delay_cb, C.c_void_p).value


def fresh(dev):
    global sim
    sim = dev
    input_init()
    reset_all()
    events.clear()
    register(C.cast(on_event, C.c_void_p), 0)


def report(*parts):
    """Queue a report, ask for service, and return the events it made."""
    sim.queue.append(b"".join(parts))
    events.clear()
    attention(0)
    service()
    pump()
    return list(events)


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# a touchpad descriptor with its switches in their own feature report
switches = b"".join([
    UsagePage(0x0D), Usage(0x0E), Collection_(APPLICATION), ReportID(4),
    Usage(0x22), Collection_(LOGICAL), Usage(0x57), Usage(0x58), LogMax(1), Size(1), Count(2), Feature(VAR),
    Count(6), Feature(CONST), End, End])
tp_desc = touchpad + switches


def fingers(*fs, count=None, button=0):
    """Report 1: up to five (conf, tip, id, x, y) fingers."""
    rows = list(fs) + [(0, 0, 0, 0, 0)] * (5 - len(fs))
    bits = [v for f in rows for v in ((f[0], 1), (f[1], 1), (0, 6), (f[2], 8), (f[3], 16), (f[4], 16))]
    bits += [(0, 16), (len(fs) if count is None else count, 8), (button, 1), (0, 7)]
    v, off = 0, 0
    for value, size in bits:
        v |= (value & ((1 << size) - 1)) << off
        off += size
    return b"\x01" + v.to_bytes(off // 8, "little")


# --- bring-up ------------------------------------------------------------------------------
fresh(SimI2cHid(tp_desc))
check("probe", probe(0, 0x2C, DESC_REG), 0)
check("powered on, reset once", (sim.power, sim.resets), (0, 1))
check("waited for the reset", len(delays) >= 1, True)
check("multi-touch mode set", sim.features.get(3), b"\x03")
check("surface and button switches on", sim.features.get(4), b"\x03")
info = DevInfo.from_address(dev_info(1))
check("device", (info.name, info.bus, info.caps, info.vendor, info.product),
      (b"I2C touchpad", 5, 4 | 2, 0x1234, 0x5678))
check("ranges, resolution, slots", (info.max_x, info.max_y, info.res_x, info.res_y, info.slots),
      (4095, 2470, 33, 31, 5))

# --- touch -------------------------------------------------------------------------------------
after = []
AFTER = C.CFUNCTYPE(None, C.c_uint64)
after_cb = AFTER(lambda c: after.append(c))
set_after(0, C.cast(after_cb, C.c_void_p), 0xBEEF)
ev = report(fingers((1, 1, 3, 1000, 2000), (1, 1, 5, 3000, 100)))
FRAME = (TOUCH, 3 << 8, 0)
check("two fingers down, then a frame end",
      ev, [(TOUCH, 3 | 1 << 12, 1000 | 2000 << 16), (TOUCH, 5 | 1 << 12, 3000 | 100 << 16), FRAME])
check("the after function ran with its cookie", after, [0xBEEF])
ev = report(fingers((1, 1, 3, 1040, 2020)))
check("finger 3 moves, the pointer follows, finger 5 has lifted",
      ev, [(TOUCH, 3 | 1 << 8 | 1 << 12, 1040 | 2020 << 16), (MOTION, 10, 5), (TOUCH, 5 | 2 << 8, 0), FRAME])
ev = report(fingers((0, 1, 3, 1042, 2021)))
check("a palm (no confidence) is still a contact, marked; motion below a step waits",
      ev, [(TOUCH, 3 | 1 << 8, 1042 | 2021 << 16), FRAME])
ev = report(fingers((1, 1, 3, 1044, 2022)))
check("remainders add up to a step", [e for e in ev if e[0] == MOTION], [(MOTION, 1, 0)])
ev = report(fingers((1, 0, 3, 1044, 2022), count=1))
check("tip released: up", ev, [(TOUCH, 3 | 2 << 8, 0), FRAME])
ev = report(fingers((1, 1, 7, 500, 500), button=1))
check("click", ev[-1], (BUTTON, 0, 1))
ev = report(fingers((1, 1, 7, 500, 500), button=1))
check("held click does not repeat", [e for e in ev if e[0] == BUTTON], [])
ev = report(fingers((1, 1, 7, 500, 500), button=0))
check("release", ev[-1], (BUTTON, 0, 0))
C.c_uint32.in_dll(lib, "i2c_hid_pointer_emulation").value = 0
report(fingers((1, 1, 7, 500, 500)))
ev = report(fingers((1, 1, 7, 900, 900)))
check("pointer emulation off", [e for e in ev if e[0] == MOTION], [])
C.c_uint32.in_dll(lib, "i2c_hid_pointer_emulation").value = 1
ev = report(fingers((1, 1, 40, 1, 1)))
check("a contact ID past the slots is ignored",
      [e for e in ev if e[0] == TOUCH and e[1] & 0xFF == 40], [])
check("an empty report makes nothing", report(b""), [])
sim.queue.append(b"\x01")
events.clear()
attention(0)
service()
pump()
check("a report shorter than its ID and data is dropped", (events, counter("i2c_hid_bad_reports").value), ([], 1))
events.clear()
check("no attention: no transfer", (service(), events), (0, []))

# --- a mouse ------------------------------------------------------------------------------------
fresh(SimI2cHid(mouse))
check("mouse probe", probe(0, 0x15, DESC_REG), 0)
check("mouse device", DevInfo.from_address(dev_info(1)).name, b"I2C mouse")
m = struct.pack("<Bbbb", 0b001, -3, 4, 1)
check("motion, wheel, left button", report(m), [(MOTION, -3, 4), (AXIS, 0, -1), (BUTTON, 0, 1)])
check("buttons change one at a time", report(struct.pack("<Bbbb", 0b110, 0, 0, 0)),
      [(BUTTON, 0, 0), (BUTTON, 1, 1), (BUTTON, 2, 1)])

# --- failures --------------------------------------------------------------------------------------
fresh(SimI2cHid(mouse, present=False))
check("nobody at the address", probe(0, 0x2C, DESC_REG), -ENODEV)
fresh(SimI2cHid(mouse, bcd=0x0200))
check("not an I2C-HID 1.0 descriptor", probe(0, 0x2C, DESC_REG), -ENODEV)
fresh(SimI2cHid(mouse, max_input=1))
check("an input length too small", probe(0, 0x2C, DESC_REG), -EINVAL)
fresh(SimI2cHid(b"\x05"))
check("a broken report descriptor", probe(0, 0x2C, DESC_REG), -EINVAL)
fresh(SimI2cHid(mouse))
probe(0, 1, DESC_REG)
probe(0, 2, DESC_REG)
check("two devices at most", probe(0, 3, DESC_REG), -ENOSPC)

print(f"test_i2c_hid: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

"""I2C host tests: attach, timing, transfers, errors.

usage: python3 test_i2c.py path/to/i2c.so
"""
import ctypes as C
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim_dw import (SimDW, RegDevice, CON, TAR, SS_HCNT, SS_LCNT, FS_HCNT, FS_LCNT,  # noqa: E402
                    SDA_HOLD, READ, STOP, RESTART)

lib = C.CDLL(sys.argv[1])
EIO, ENXIO, EINVAL, ENODEV, ENOSPC, ETIMEDOUT = 5, 6, 22, 19, 28, 110
M_READ, M_TEN = 1, 2
BASE = 0x7D000000


class Msg(C.Structure):
    _fields_ = [("addr", C.c_uint16), ("flags", C.c_uint16), ("len", C.c_uint32), ("buf", C.c_void_p)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


U, P, I = C.c_uint32, C.c_uint64, C.c_int32
attach = fn("i2c_dw_attach", I, P, U)
detach_all = fn("i2c_detach_all", None)
set_speed = fn("i2c_dw_set_speed", I, U, U, U, U, U)
xfer = fn("i2c_xfer", I, U, C.c_void_p, U)
write_read = fn("i2c_write_read", I, U, U, C.c_void_p, U, C.c_void_p, U)
counter = lambda n: C.c_uint32.in_dll(lib, n).value  # noqa: E731
RD = C.CFUNCTYPE(C.c_uint32, C.c_uint64)
WR = C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)
hook_rd = C.c_void_p.in_dll(lib, "i2c_read32_fn")
hook_wr = C.c_void_p.in_dll(lib, "i2c_write32_fn")
keep = []


def fresh(clock=133000, **kw):
    detach_all()
    sim = SimDW(**kw)
    sims = {BASE: sim}

    def rd(a):
        base = a & ~0xFFF
        return sims[base].read(a - base) if base in sims else 0

    def wr(a, v):
        base = a & ~0xFFF
        if base in sims:
            sims[base].write(a - base, v)
    r, w = RD(rd), WR(wr)
    keep.extend([r, w])
    hook_rd.value = C.cast(r, C.c_void_p).value
    hook_wr.value = C.cast(w, C.c_void_p).value
    sim.others = sims
    return sim, attach(BASE, clock)


def msgs(*specs):
    """(addr, flags, data or length) ... → array, buffers."""
    arr = (Msg * len(specs))()
    bufs = []
    for i, (addr, flags, data) in enumerate(specs):
        b = C.create_string_buffer(bytes(data) if not isinstance(data, int) else data,
                                   len(data) if not isinstance(data, int) else max(data, 1))
        bufs.append(b)
        arr[i].addr, arr[i].flags = addr, flags
        arr[i].len = len(data) if not isinstance(data, int) else data
        arr[i].buf = C.addressof(b)
    return arr, bufs


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# --- attach and timing -------------------------------------------------------------------------
sim, c = fresh(comp_type=0x12345678)
check("not a DesignWare controller", c, -ENODEV)
sim, c = fresh()
check("attach", c, 0)
check("400 kHz from a 133 MHz clock", (sim.regs.get(FS_HCNT), sim.regs.get(FS_LCNT)), (73, 172))
for base in (0x1000, 0x2000, 0x3000):
    s2 = SimDW()
    sim.others[BASE + base] = s2
    attach(BASE + base, 0)
s5 = SimDW()
sim.others[BASE + 0x4000] = s5
check("no fifth controller", attach(BASE + 0x4000, 0), -ENOSPC)
check("no base", attach(0, 1), -EINVAL)
check("100 kHz", (set_speed(0, 100000, 0, 0, 0), sim.regs.get(SS_HCNT), sim.regs.get(SS_LCNT)), (0, 525, 625))
check("1 MHz", (set_speed(0, 1000000, 0, 0, 0), sim.regs.get(FS_HCNT), sim.regs.get(FS_LCNT)), (0, 28, 66))
check("counts from ACPI, and SDA hold", (set_speed(0, 400000, 0x55, 0x99, 0x1E), sim.regs.get(FS_HCNT),
                                         sim.regs.get(FS_LCNT), sim.regs.get(SDA_HOLD)), (0, 0x55, 0x99, 0x1E))
check("too fast", set_speed(0, 3400000, 0, 0, 0), -EINVAL)
check("no clock and no counts", set_speed(1, 400000, 0, 0, 0), -EINVAL)
check("no such controller", set_speed(3 + 1, 400000, 1, 1, 0), -EINVAL)

# --- transfers ----------------------------------------------------------------------------------
sim, c = fresh()
descriptor = bytes(range(0x10, 0x10 + 30))
hid = RegDevice({0x0001 + i: b for i, b in enumerate(descriptor)}, width=2)
hid.mem = {0x0001 + i: b for i, b in enumerate(descriptor)}
sim.devices[0x2C] = hid
reg = C.create_string_buffer(b"\x01\x00", 2)
out = C.create_string_buffer(30)
check("register read (the I2C-HID descriptor)", write_read(0, 0x2C, reg, 2, out, 30), 0)
check("bytes read", out.raw, descriptor)
check("control: master, fast, restart, no slave", sim.regs.get(CON), 0x65)
check("target", sim.regs.get(TAR), 0x2C)
check("commands: 2 writes, a repeated start, reads, a stop at the end",
      ([c_ & 0xFF for c_ in sim.cmds[:2]], sim.cmds[2], sim.cmds[-1] & (READ | STOP), len(sim.cmds)),
      ([1, 0], READ | RESTART, READ | STOP, 32))
check("device saw start, restart, stop", (hid.log[0], "restart" in hid.log, hid.log[-1]), ("start", True, "stop"))

mem = RegDevice(width=1)
sim.devices[0x50] = mem
w = C.create_string_buffer(b"\x10\xAA\xBB", 3)
check("plain write", write_read(0, 0x50, w, 3, None, 0), 0)
check("written", (mem.mem.get(0x10), mem.mem.get(0x11)), (0xAA, 0xBB))
check("the last write has the stop", sim.cmds[-1], 0xBB | STOP)
r = C.create_string_buffer(2)
check("plain read (continues from the register)", (write_read(0, 0x50, None, 0, r, 2), r.raw), (0, b"\xFF\xFF"))
arr, bufs = msgs((0x50, 0, b"\x10"), (0x50, M_READ, 1), (0x50, M_READ, 1))
check("three messages", xfer(0, arr, 3), 0)
check("reads land in order", (bufs[1].raw[:1], bufs[2].raw[:1]), (b"\xAA", b"\xBB"))
big = RegDevice({i: i & 0xFF for i in range(300)}, width=1)
sim.devices[0x51] = big
big_out = C.create_string_buffer(300)
check("300-byte read", (write_read(0, 0x51, C.create_string_buffer(b"\x00", 1), 1, big_out, 300),
                        big_out.raw == bytes(i & 0xFF for i in range(300))), (0, True))

# --- errors ------------------------------------------------------------------------------------
check("nobody at the address", write_read(0, 0x33, reg, 2, out, 4), -ENXIO)
check("abort counted, source kept", (counter("i2c_aborts"), counter("i2c_last_abort")), (1, 1))
check("works again after an abort", write_read(0, 0x2C, reg, 2, out, 30), 0)
sim.devices[0x52] = RegDevice(width=1, nack_after=1)
check("data not acknowledged", write_read(0, 0x52, w, 3, None, 0), -EIO)
sim.devices[0x123] = RegDevice(width=1)
arr, bufs = msgs((0x123, M_TEN, b"\x00\x01"))
check("10-bit address", (xfer(0, arr, 1), sim.regs.get(TAR), sim.regs.get(CON) & 0x10), (0, 0x123 | 0x1000, 0x10))
arr, bufs = msgs((0x2D, M_TEN, b"\x00"))
check("10-bit address not answered", xfer(0, arr, 1), -ENXIO)
check("no messages", xfer(0, arr, 0), -EINVAL)
arr, bufs = msgs((0x50, 0, b"\x00"), (0x51, M_READ, 1))
check("two targets in one transfer", xfer(0, arr, 2), -EINVAL)
arr, bufs = msgs((0x50, 0, b"\x00"), (0x50, M_READ, 0))
check("a message with no bytes", xfer(0, arr, 2), -EINVAL)
check("no such controller", xfer(2, arr, 1), -EINVAL)
sim.stuck_busy = True
check("bus never idle", write_read(0, 0x2C, reg, 2, out, 4), -ETIMEDOUT)
sim.stuck_busy = False
sim.stuck_enabled = True
check("controller never turns off", write_read(0, 0x2C, reg, 2, out, 4), -ETIMEDOUT)
sim.stuck_enabled = False
sim.fifo_full = True
check("FIFO never has room", write_read(0, 0x2C, reg, 2, out, 4), -ETIMEDOUT)
sim.fifo_full = False
check("timeouts counted", counter("i2c_timeouts"), 3)
check("fine again", write_read(0, 0x2C, reg, 2, out, 30), 0)

print(f"test_i2c: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

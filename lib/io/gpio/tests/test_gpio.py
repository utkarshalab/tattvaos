"""GPIO host tests: ownership, pin settings, interrupts, storms.

usage: python3 test_gpio.py path/to/gpio.so
"""
import ctypes as C
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim_amd import SimAMD, INT_ENABLE, INT_DELIVER, LEVEL_TRIG, INT_STATUS  # noqa: E402

lib = C.CDLL(sys.argv[1])
EBUSY, ENODEV, EINVAL, ENOSPC = 16, 19, 22, 28
EDGE, LOW, BOTH = 1, 2, 4
PULL_NONE, PULL_UP, PULL_DOWN = 0, 1, 2
OWNER, OTHER = 0x1111, 0x2222
BASE = 0x7E000000                      # never dereferenced: the hooks catch it


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


U, P, I = C.c_uint32, C.c_uint64, C.c_int32
attach = fn("gpio_amd_attach", I, P, U)
detach_all = fn("gpio_detach_all", None)
claim = fn("gpio_claim", I, U, U, P)
release = fn("gpio_release", I, U, U, P)
get = fn("gpio_get", I, U, U)
gset = fn("gpio_set", I, U, U, P, U)
direction = fn("gpio_direction", I, U, U, P, U, U)
pull = fn("gpio_pull", I, U, U, P, U)
debounce = fn("gpio_debounce", I, U, U, P, U)
wake = fn("gpio_wake", I, U, U, P, U)
HANDLER = C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)
irq_setup = fn("gpio_irq_setup", I, U, U, P, U, C.c_void_p, P)
irq_unmask = fn("gpio_irq_unmask", I, U, U, P)
irq_disable = fn("gpio_irq_disable", I, U, U, P)
irq = fn("gpio_irq", I, U)
counter = lambda n: C.c_uint32.in_dll(lib, n).value  # noqa: E731

RD = C.CFUNCTYPE(C.c_uint32, C.c_uint64)
WR = C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)
hook_rd = C.c_void_p.in_dll(lib, "gpio_read32_fn")
hook_wr = C.c_void_p.in_dll(lib, "gpio_write32_fn")
hook_clock = C.c_void_p.in_dll(lib, "gpio_clock_fn")
CLOCK = C.CFUNCTYPE(C.c_uint64)
keep = []
calls = []


def on_irq(cookie, pin):
    calls.append((cookie, pin))


handler = HANDLER(on_irq)
HANDLER_P = C.cast(handler, C.c_void_p)


def fresh(pins=256, clock=None):
    detach_all()
    calls.clear()
    sim = SimAMD(BASE, pins)
    rd = RD(lambda a: sim.read(a - BASE))
    wr = WR(lambda a, v: sim.write(a - BASE, v))
    keep.extend([rd, wr])
    hook_rd.value = C.cast(rd, C.c_void_p).value
    hook_wr.value = C.cast(wr, C.c_void_p).value
    if clock:
        c = CLOCK(clock)
        keep.append(c)
        hook_clock.value = C.cast(c, C.c_void_p).value
    else:
        hook_clock.value = None
    ctrl = attach(BASE, pins)
    assert ctrl == 0, ctrl
    return sim


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# --- controllers and ownership --------------------------------------------------------------
sim = fresh()
check("second controller", attach(BASE + 0x1000, 64), 1)
check("no third", attach(BASE + 0x2000, 64), -ENOSPC)
check("bad pin count", (attach(BASE, 0), attach(BASE, 257)), (-EINVAL, -EINVAL))
check("no base", attach(0, 8), -EINVAL)
sim = fresh(pins=64)
check("claim", claim(0, 9, OWNER), 0)
check("claim again by the owner", claim(0, 9, OWNER), 0)
check("claim by another", claim(0, 9, OTHER), -EBUSY)
check("claim with no owner", claim(0, 10, 0), -EINVAL)
check("pin past the controller", claim(0, 64, OWNER), -EINVAL)
check("no such controller", claim(1, 1, OWNER), -EINVAL)
check("another's pin cannot be set", gset(0, 9, OTHER, 1), -EBUSY)
check("an unclaimed pin cannot be set", gset(0, 11, OWNER, 1), -EINVAL)
check("anyone may read", get(0, 9), 0)
check("release by another", release(0, 9, OTHER), -EBUSY)
check("release", release(0, 9, OWNER), 0)
check("free again", claim(0, 9, OTHER), 0)

# --- pin settings ----------------------------------------------------------------------------
sim = fresh()
claim(0, 5, OWNER)
sim.inputs[5] = 1
check("read the level", get(0, 5), 1)
check("output with a starting value", direction(0, 5, OWNER, 1, 1), 0)
check("output enabled, value 1", sim.pin_reg(5) & (3 << 22), 3 << 22)
check("drive low", (gset(0, 5, OWNER, 0), sim.pin_reg(5) & (1 << 22)), (0, 0))
check("back to input", (direction(0, 5, OWNER, 0, 0), sim.pin_reg(5) & (1 << 23)), (0, 0))
check("pull up", (pull(0, 5, OWNER, PULL_UP), sim.pin_reg(5) & (3 << 20)), (0, 1 << 20))
check("pull down", (pull(0, 5, OWNER, PULL_DOWN), sim.pin_reg(5) & (3 << 20)), (0, 1 << 21))
check("no pull", (pull(0, 5, OWNER, PULL_NONE), sim.pin_reg(5) & (3 << 20)), (0, 0))
check("bad pull", pull(0, 5, OWNER, 3), -EINVAL)
DB = 0xFF                               # time, unit, control, large
cases = [(0, 0x00), (30, 0x61), (500, 0x68), (2000, 0x78), (50000, 0xE3), (500000, 0xF8)]
for us, bits in cases:
    debounce(0, 5, OWNER, us)
    check(f"debounce {us} us", sim.pin_reg(5) & DB, bits)
check("debounce too long", debounce(0, 5, OWNER, 1000000), -EINVAL)
check("wake on", (wake(0, 5, OWNER, 1), sim.pin_reg(5) & (7 << 13)), (0, 7 << 13))
check("wake off", (wake(0, 5, OWNER, 0), sim.pin_reg(5) & (7 << 13)), (0, 0))
sim.regs[5 * 4] |= INT_STATUS
pull(0, 5, OWNER, PULL_UP)
check("settings never clear a pending status", sim.pin_reg(5) & INT_STATUS, INT_STATUS)

# --- interrupts ----------------------------------------------------------------------------------
sim = fresh()
claim(0, 9, OWNER)
sim.inputs[9] = 1                       # the line idles high
check("level, active low (the touchpad's line)", irq_setup(0, 9, OWNER, LOW, HANDLER_P, 0xAB), 0)
r = sim.pin_reg(9)
check("level trigger, active low, enabled, delivered",
      (bool(r & LEVEL_TRIG), (r >> 9) & 3, bool(r & INT_ENABLE), bool(r & INT_DELIVER)), (True, 1, True, True))
sim.drive(9, 1)
check("idle line: nothing", (irq(0), calls), (0, []))
sim.drive(9, 0)                         # the device asserts
check("asserted: handler with its cookie and pin", (irq(0), calls), (1, [(0xAB, 9)]))
check("end of interrupt sent", sim.eois, 2)
check("masked until serviced", sim.pin_reg(9) & INT_DELIVER, 0)
check("still asserted but masked: nothing", irq(0), 0)
sim.drive(9, 1)                         # the driver read the device; it lets go
check("unmask", irq_unmask(0, 9, OWNER), 0)
check("released: nothing more", irq(0), 0)
sim.drive(9, 0)
check("next report", irq(0), 1)
check("unmask by another", irq_unmask(0, 9, OTHER), -EBUSY)
irq_unmask(0, 9, OWNER)                 # still asserted from "next report"
check("a line still asserted at unmask fires again", irq(0), 1)

sim = fresh()
claim(0, 130, OWNER)
irq_setup(0, 130, OWNER, EDGE, HANDLER_P, 7)
check("edge pin in the second summary register", (sim.drive(130, 1), irq(0), calls), (None, 1, [(7, 130)]))
check("edge pin stays delivered", bool(sim.pin_reg(130) & INT_DELIVER), True)
check("status cleared", sim.pin_reg(130) & INT_STATUS, 0)
check("falling edge ignored on a rising pin", (sim.drive(130, 0), irq(0)), (None, 0))
claim(0, 3, OWNER)
irq_setup(0, 3, OWNER, EDGE | BOTH, HANDLER_P, 8)
check("both edges", ((sim.pin_reg(3) >> 9) & 3), 2)
sim.drive(3, 1)
sim.drive(130, 1)
calls.clear()
check("two pins in one interrupt", (irq(0), sorted(calls)), (2, [(7, 130), (8, 3)]))
check("both edges without edge mode", irq_setup(0, 3, OWNER, BOTH, HANDLER_P, 8), -EINVAL)
check("no handler", irq_setup(0, 3, OWNER, EDGE, None, 0), -EINVAL)

sim = fresh()
sim.regs[20 * 4] = INT_ENABLE | INT_DELIVER | INT_STATUS   # firmware left one on
check("an interrupt nobody wants", (irq(0), counter("gpio_spurious")), (0, 1))
check("is turned off", sim.pin_reg(20) & (INT_ENABLE | INT_DELIVER | INT_STATUS), 0)
claim(0, 21, OWNER)
irq_setup(0, 21, OWNER, EDGE, HANDLER_P, 1)
check("disable", (irq_disable(0, 21, OWNER), sim.pin_reg(21) & (INT_ENABLE | INT_DELIVER)), (0, 0))
check("release turns it off too", (irq_setup(0, 21, OWNER, EDGE, HANDLER_P, 1), release(0, 21, OWNER),
                                   sim.pin_reg(21) & INT_ENABLE), (0, 0, 0))
check("not a controller", irq(1), -EINVAL)

# --- storms ------------------------------------------------------------------------------------------
now = [0]
sim = fresh(clock=lambda: now[0])
claim(0, 4, OWNER)
irq_setup(0, 4, OWNER, EDGE, HANDLER_P, 4)
for i in range(10001):
    sim.drive(4, 1)
    irq(0)
    sim.drive(4, 0)
check("10000 interrupts in a second are fine", (len(calls), counter("gpio_storms")), (10000, 1))
check("the 10001st masks the pin", sim.pin_reg(4) & INT_DELIVER, 0)
sim.drive(4, 1)
check("masked: no more", (irq(0), len(calls)), (0, 10000))
check("unmask after a storm", (irq_unmask(0, 4, OWNER), sim.pin_reg(4) & INT_DELIVER), (0, INT_DELIVER))
now[0] = 2_000_000_000
sim.drive(4, 0)
sim.drive(4, 1)
check("a new window", (irq(0), counter("gpio_storms")), (1, 1))

print(f"test_gpio: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

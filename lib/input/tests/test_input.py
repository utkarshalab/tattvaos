"""lib/input host tests: event core and PS/2 keyboard.

usage: python3 test_input.py path/to/input.so
"""
import ctypes as C
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sim_ps2 import SimPS2  # noqa: E402

lib = C.CDLL(sys.argv[1])

EIO, EBUSY, ENODEV, EINVAL, ENOSPC = 5, 16, 19, 22, 28
INPUT_KEY = 1
BUS_PS2, CAP_KEYBOARD = 4, 1


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_uint32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class DevInfo(C.Structure):
    _fields_ = [("id", C.c_uint32), ("pad0", C.c_uint32), ("name", C.c_char_p),
                ("bus", C.c_uint32), ("vendor", C.c_uint16), ("product", C.c_uint16),
                ("version", C.c_uint16), ("pad1", C.c_uint16 * 3), ("caps", C.c_uint64),
                ("max_x", C.c_int32), ("max_y", C.c_int32),
                ("res_x", C.c_uint32), ("res_y", C.c_uint32),
                ("slots", C.c_uint32), ("pad2", C.c_uint32)]


assert C.sizeof(Event) == 24 and C.sizeof(DevInfo) == 64

INB = C.CFUNCTYPE(C.c_uint8, C.c_uint64)
OUTB = C.CFUNCTYPE(None, C.c_uint64, C.c_uint64)
CLOCK = C.CFUNCTYPE(C.c_uint64)
EVCB = C.CFUNCTYPE(None, C.POINTER(Event), C.c_void_p)


def fn(name, res, *args):
    f = getattr(lib, name)
    f.restype = res
    f.argtypes = list(args)
    return f


input_init = fn("input_init", None)
input_post = fn("input_post", C.c_int32, C.c_uint32, C.c_uint32, C.c_int32, C.c_uint32)
input_pump = fn("input_pump", C.c_int32)
dev_add = fn("input_dev_add", C.c_int32, C.c_char_p, C.c_uint32, C.c_uint64, C.c_uint32)
dev_remove = fn("input_dev_remove", C.c_int32, C.c_uint32)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
unregister = fn("ut_input_unregister_callback", C.c_int64)
dev_info = fn("ut_input_device_info", C.c_int64, C.c_uint32)
grab = fn("ut_input_grab", C.c_int64, C.c_uint32, C.c_uint32)
ps2_init = fn("ps2_init", C.c_int32)
irq_enable = fn("i8042_irq_enable", None)
i8042_irq = fn("i8042_irq", C.c_int32)
kbd_service = fn("ps2_kbd_service", None)


def u32(name):
    return C.c_uint32.in_dll(lib, name)


hook_in = C.c_void_p.in_dll(lib, "input_port_in8_fn")
hook_out = C.c_void_p.in_dll(lib, "input_port_out8_fn")
hook_clock = C.c_void_p.in_dll(lib, "input_clock_fn")

keep = []           # ctypes callbacks must outlive their use
sim = None
events = []


def use(s):
    global sim
    sim = s
    cin, cout = INB(lambda p: s.inb(p)), OUTB(lambda p, v: s.outb(p, v))
    keep.extend([cin, cout])
    hook_in.value = C.cast(cin, C.c_void_p).value
    hook_out.value = C.cast(cout, C.c_void_p).value


def on_event(ev, cookie):
    e = ev.contents
    events.append((e.type, e.code, e.value, e.device, e.time, cookie))


event_cb = EVCB(on_event)
COOKIE = 0x1234


def fresh(clock=None):
    """Empty state, a callback registered, an optional clock."""
    input_init()
    events.clear()
    if clock is None:
        hook_clock.value = None
    else:
        c = CLOCK(clock)
        keep.append(c)
        hook_clock.value = C.cast(c, C.c_void_p).value
    assert register(C.cast(event_cb, C.c_void_p), COOKIE) == 0


def keyboard(**kw):
    """A fresh state with a working keyboard, interrupt on."""
    fresh(**kw)
    use(SimPS2())
    assert ps2_init() == 0
    irq_enable()
    sim.instant = False
    return sim


def type_bytes(*codes):
    sim.keys(*codes)
    i8042_irq()
    input_pump()
    keys = [(t, c, v) for (t, c, v, *_rest) in events]
    events.clear()
    return keys


failures = 0
passed = 0


def check(name, cond, detail=""):
    global failures, passed
    if cond:
        passed += 1
    else:
        failures += 1
        print(f"FAIL {name} {detail}")


# --- event core ---------------------------------------------------------------
fresh()
check("register again is busy", register(C.cast(event_cb, C.c_void_p), 0) == -EBUSY)
unregister()
check("register null is invalid", register(None, 0) == -EINVAL)
check("register after unregister", register(C.cast(event_cb, C.c_void_p), COOKIE) == 0)

fresh()
d = dev_add(b"test device", 8, 2, 0x12345678)
check("first device is 1", d == 1, d)
p = dev_info(d)
info = DevInfo.from_address(p)
check("device info", (info.id, info.name, info.bus, info.caps, info.vendor, info.product)
      == (1, b"test device", 8, 2, 0x1234, 0x5678), (info.id, info.name))
check("device info: unlisted bytes are 0",
      (info.pad0, info.version, list(info.pad1), info.slots, info.pad2) == (0, 0, [0, 0, 0], 0, 0))
check("slots at offset 56",
      DevInfo.slots.offset, 56)
check("unknown device info", dev_info(7) == -ENODEV)
check("device 0 is never valid", dev_info(0) == -ENODEV)
check("grab", grab(d, 1) == 0)
check("grab twice is busy", grab(d, 1) == -EBUSY)
check("release", grab(d, 0) == 0)
check("grab unknown", grab(9, 1) == -ENODEV)
check("remove", dev_remove(d) == 0 and dev_info(d) == -ENODEV)
check("remove twice", dev_remove(d) == -ENODEV)

fresh()
ids = [dev_add(b"x" * 50, 8, 0, 0) for _ in range(33)]
check("32 devices fit", ids[:32] == list(range(1, 33)), ids[:3])
check("33rd device has no room", ids[32] == -ENOSPC, ids[32])
check("long names are cut", DevInfo.from_address(dev_info(1)).name == b"x" * 31)
dev_remove(5)
check("a freed ID is reused", dev_add(b"y", 8, 0, 0) == 5)

fresh(clock=lambda: 777)
input_post(INPUT_KEY, 30, 1, 3)
check("nothing is delivered before the pump", events == [])
check("pump returns the count", input_pump() == 1)
check("event delivered with time and cookie", events == [(1, 30, 1, 3, 777, COOKIE)], events)

fresh()
for i in range(300):
    input_post(INPUT_KEY, i & 0xFF, 1, 1)
check("ring keeps 256", input_pump() == 256)
check("ring drops the rest", u32("input_dropped").value == 44)
check("time 0 without a clock", events[0][4] == 0)

fresh()
unregister()
input_post(INPUT_KEY, 1, 1, 1)
input_pump()
check("no callback: discarded", u32("input_discarded").value == 1 and events == [])

# --- PS/2 start-up ----------------------------------------------------------------
fresh()
use(SimPS2(present=False))
check("no controller", ps2_init() == -ENODEV)
check("no controller: no device", dev_info(1) == -ENODEV)

fresh()
use(SimPS2(selftest=0xFC))
check("failed self-test", ps2_init() == -EIO)

fresh()
use(SimPS2(kbd_present=False))
check("no keyboard", ps2_init() == -ENODEV)

fresh()
s = SimPS2()
use(s)
check("ps2_init", ps2_init() == 0)
info = DevInfo.from_address(dev_info(1))
check("keyboard device", (info.name, info.bus, info.caps) == (b"PS/2 keyboard", BUS_PS2, CAP_KEYBOARD))
check("translation on, interrupts off after init", (s.cfg & 0x43) == 0x40, hex(s.cfg))
check("configuration rewritten after the self-test", s.commands.index(0xAA) < len(s.commands) - 1
      and s.cfg != 0)
check("keyboard reset, set 2, LEDs off, enabled",
      s.kbd_enabled and s.scanset == 2 and s.leds == 0 and s.kbd_writes[0] == 0xFF, s.kbd_writes)
irq_enable()
check("interrupt on", (s.cfg & 0x11) == 0x01, hex(s.cfg))

fresh()
s = SimPS2()
s.resend_next = 1               # the reset is asked for again once
use(s)
check("reset retried after RESEND", ps2_init() == 0 and s.kbd_writes[:2] == [0xFF, 0xFF], s.kbd_writes)

# --- decoding --------------------------------------------------------------------------
keyboard()
check("a press and release", type_bytes(0x1E, 0x9E) == [(1, 30, 1), (1, 30, 0)])
keyboard(clock=lambda: 42)
sim.keys(0x10)
i8042_irq()
input_pump()
check("events carry device and time", events == [(1, 16, 1, 1, 42, COOKIE)], events)

keyboard()
check("arrow up", type_bytes(0xE0, 0x48, 0xE0, 0xC8) == [(1, 103, 1), (1, 103, 0)])
check("right ctrl", type_bytes(0xE0, 0x1D, 0xE0, 0x9D) == [(1, 97, 1), (1, 97, 0)])
check("super", type_bytes(0xE0, 0x5B, 0xE0, 0xDB) == [(1, 125, 1), (1, 125, 0)])
check("keypad enter", type_bytes(0xE0, 0x1C, 0xE0, 0x9C) == [(1, 96, 1), (1, 96, 0)])
check("volume up", type_bytes(0xE0, 0x30, 0xE0, 0xB0) == [(1, 115, 1), (1, 115, 0)])
check("print screen drops the added shifts",
      type_bytes(0xE0, 0x2A, 0xE0, 0x37, 0xE0, 0xB7, 0xE0, 0xAA) == [(1, 99, 1), (1, 99, 0)])
check("pause", type_bytes(0xE1, 0x1D, 0x45, 0xE1, 0x9D, 0xC5) == [(1, 119, 1), (1, 119, 0)])
check("keyboard repeats dropped", type_bytes(0x1F, 0x1F, 0x1F, 0x9F) == [(1, 31, 1), (1, 31, 0)])
check("left shift release (0xAA) is a key", type_bytes(0x2A, 0xAA) == [(1, 42, 1), (1, 42, 0)])
check("F12", type_bytes(0x58, 0xD8) == [(1, 88, 1), (1, 88, 0)])
check("release without a press", type_bytes(0x9E) == [])
check("unknown code", type_bytes(0x59) == [] and u32("ps2_kbd_unknown").value == 1)
check("overrun", type_bytes(0x00, 0xFF) == [] and u32("ps2_kbd_overruns").value == 2)
sim.aux(0x08, 0x01, 0x01)
sim.error_byte(0x1E)
i8042_irq()
input_pump()
check("mouse bytes and bad bytes dropped",
      events == [] and u32("i8042_aux_bytes").value == 3 and u32("i8042_errors").value == 1)
events.clear()

# --- LEDs ------------------------------------------------------------------------------
keyboard()
check("caps lock press", type_bytes(0x3A) == [(1, 58, 1)])
kbd_service()
check("LED command sent", sim.kbd_writes[-1] == 0xED, sim.kbd_writes)
sim.deliver()               # ACK for 0xED
i8042_irq()
check("LED byte sent on the ACK", sim.kbd_writes[-1] == 0x04, sim.kbd_writes)
sim.deliver()               # ACK for the LED byte
i8042_irq()
check("caps LED on", sim.leds == 0x04 and u32("ps2_kbd_cmd_state").value == 0)
check("caps lock release changes nothing", type_bytes(0xBA) == [(1, 58, 0)])
kbd_service()
check("no LED work after a release", sim.kbd_writes[-1] == 0x04)
type_bytes(0x45, 0xC5)      # num lock
kbd_service()
sim.deliver(); i8042_irq(); sim.deliver(); i8042_irq()
check("caps and num LEDs", sim.leds == 0x06, sim.leds)
check("ACKs are not keys", events == [])

keyboard()
type_bytes(0x46)            # scroll lock
sim.resend_next = 1
kbd_service()
sim.deliver(); i8042_irq()  # RESEND → 0xED again
check("LED command resent", sim.kbd_writes[-2:] == [0xED, 0xED] and u32("ps2_kbd_resends").value == 1,
      sim.kbd_writes)
sim.deliver(); i8042_irq(); sim.deliver(); i8042_irq()
check("scroll LED on after a resend", sim.leds == 0x01, sim.leds)

keyboard()
type_bytes(0x3A)
sim.kbd_present = False     # the keyboard stops answering
kbd_service()               # sends 0xED; no ACK will come
for _ in range(100000):
    kbd_service()
check("lost LED exchange given up", u32("ps2_kbd_led_timeouts").value == 1
      and u32("ps2_kbd_cmd_state").value == 0)

t = [0]
keyboard(clock=lambda: t[0])
type_bytes(0x3A)
sim.kbd_present = False
kbd_service()
t[0] = 49_000_000
kbd_service()
check("49 ms is not a timeout", u32("ps2_kbd_led_timeouts").value == 0)
t[0] = 51_000_000
kbd_service()
check("51 ms is a timeout", u32("ps2_kbd_led_timeouts").value == 1)

print(f"test_input: {passed} passed, {failures} failed")
sys.exit(1 if failures else 0)

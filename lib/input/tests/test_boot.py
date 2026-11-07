"""HID boot reports (hid/boot.asm): the usage → keycode table, keyboards,
mice.

usage: python3 test_boot.py path/to/input.so
"""
import ctypes as C
import sys

lib = C.CDLL(sys.argv[1])
KEY, MOTION, BUTTON, AXIS = 1, 2, 4, 5


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
_kbd = fn("hid_boot_keyboard", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
_mouse = fn("hid_boot_mouse", None, C.c_void_p, C.c_char_p, C.c_uint32)
table = (C.c_uint8 * 256).in_dll(lib, "hid_usage_key")
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731

NOOP_OFF = C.CFUNCTYPE(C.c_uint64)(lambda: 0)
NOOP_RESTORE = C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)
C.c_void_p.in_dll(lib, "input_irq_off_fn").value = C.cast(NOOP_OFF, C.c_void_p).value
C.c_void_p.in_dll(lib, "input_irq_restore_fn").value = C.cast(NOOP_RESTORE, C.c_void_p).value


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class Boot(C.Structure):
    _fields_ = [("prev", C.c_uint8 * 8), ("dev", C.c_uint32), ("buttons", C.c_uint32),
                ("locks", C.c_uint32), ("pad", C.c_uint32)]


events = []
on_event = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)(
    lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                Event.from_address(e).value, Event.from_address(e).device)))
input_init()
register(C.cast(on_event, C.c_void_p), 0)
passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def take():
    pump()
    out = events[:]
    events.clear()
    return out


kb = Boot(dev=3)
ms = Boot(dev=4)


def kbd(mods, *keys, length=8):
    r = bytes([mods, 0] + list(keys) + [0] * (6 - len(keys)))[:length]
    rc = _kbd(C.byref(kb), r, len(r))
    return rc, [(t, c, v) for t, c, v, d in take()]


# ---- the table ---------------------------------------------------------------------
spots = {0x04: 30, 0x1D: 44, 0x1E: 2, 0x27: 11, 0x28: 28, 0x29: 1, 0x2A: 14, 0x2B: 15, 0x2C: 57,
         0x2D: 12, 0x31: 43, 0x32: 43, 0x35: 41, 0x38: 53, 0x39: 58, 0x3A: 59, 0x43: 68, 0x44: 87, 0x45: 88,
         0x46: 99, 0x47: 70, 0x48: 119, 0x49: 110, 0x4C: 111, 0x4F: 106, 0x50: 105, 0x51: 108, 0x52: 103,
         0x53: 69, 0x54: 98, 0x58: 96, 0x59: 79, 0x61: 73, 0x62: 82, 0x63: 83, 0x64: 86, 0x65: 127, 0x66: 116,
         0x67: 117, 0x68: 183, 0x73: 194, 0x74: 134, 0x7E: 136, 0x7F: 113, 0x80: 115, 0x81: 114, 0x85: 121,
         0x87: 89, 0x89: 124, 0x8C: 95, 0x90: 122, 0x94: 85, 0xE0: 29, 0xE1: 42, 0xE2: 56, 0xE3: 125,
         0xE4: 97, 0xE5: 54, 0xE6: 100, 0xE7: 126}
check("usage → keycode at 62 places", {u: table[u] for u in spots}, spots)
check("letters a-z in order", [table[u] for u in range(4, 30)],
      [30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44])
check("nothing for the reserved and unused ones",
      [table[u] for u in (0, 1, 2, 3, 0x82, 0x86, 0x8D, 0x95, 0xA0, 0xDF, 0xE8, 0xFF)], [0] * 12)

# ---- keyboards -----------------------------------------------------------------------
check("a down", kbd(0, 0x04), (0, [(KEY, 30, 1)]))
check("b down too", kbd(0, 0x04, 0x05), (0, [(KEY, 48, 1)]))
check("a up, b held: order in the report does not matter", kbd(0, 0x05), (0, [(KEY, 30, 0)]))
check("left shift", kbd(0x02, 0x05), (0, [(KEY, 42, 1)]))
check("right alt and shift up together", kbd(0x40, 0x05), (0, [(KEY, 42, 0), (KEY, 100, 1)]))
check("the same report again: nothing", kbd(0x40, 0x05), (0, []))
check("ErrorRollOver: ignored, keys stay down", (kbd(0x40, 1, 1, 1, 1, 1, 1), u32("hid_boot_rollover").value),
      ((0, []), 1))
check("everything up", kbd(0), (0, [(KEY, 48, 0), (KEY, 100, 0)]))
rc, ev = kbd(0, 0x39)
check("Caps Lock: down, and the LEDs to set", (rc, ev, kb.locks), (1, [(KEY, 58, 1)], 2))
check("held: no second toggle", kbd(0, 0x39), (0, []))
kbd(0)
check("Num Lock as well", (kbd(0, 0x53)[0], kb.locks), (1, 3))
kbd(0)
check("Caps Lock again: off", (kbd(0, 0x39)[0], kb.locks), (1, 1))
kbd(0)
check("six keys at once", len(kbd(0, 4, 5, 6, 7, 8, 9)[1]), 6)
before = u32("hid_boot_unknown").value
check("a usage with no keycode", (kbd(0, 4, 5, 6, 7, 8, 0xA5)[1], u32("hid_boot_unknown").value - before),
      ([(KEY, 33, 0)], 1))                       # f (usage 9) let go
kbd(0)
check("a three-byte report (one key)", kbd(0, 0x04, length=3), (0, [(KEY, 30, 1)]))
check("too short: ignored", kbd(0, length=2), (0, []))
check("events carry the device", (_kbd(C.byref(kb), bytes(8), 8), [e[3] for e in take()]), (0, [3]))


# ---- mice ------------------------------------------------------------------------------
def mouse(*r):
    _mouse(C.byref(ms), bytes(r), len(r))
    return [(t, c, v) for t, c, v, d in take()]


check("motion", mouse(0, 5, 0xFD), [(MOTION, 5, -3)])
check("left down", mouse(1, 0, 0), [(BUTTON, 0, 1)])
check("right too, while moving", mouse(3, 1, 1), [(MOTION, 1, 1), (BUTTON, 1, 1)])
check("both up", mouse(0, 0, 0), [(BUTTON, 0, 0), (BUTTON, 1, 0)])
check("middle", mouse(4, 0, 0), [(BUTTON, 2, 1)])
check("wheel towards the user: down", mouse(4, 0, 0, 0xFF), [(AXIS, 0, 1)])
check("buttons past three ignored", mouse(0xF8, 0, 0), [(BUTTON, 2, 0)])
check("too short", mouse(1, 2), [])

print(f"test_boot: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

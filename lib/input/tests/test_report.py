"""Keyboards and mice in report protocol (hid/report.asm).

usage: python3 test_report.py path/to/input.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hid_gen as H  # noqa: E402

lib = C.CDLL(sys.argv[1])


class Field(C.Structure):
    _fields_ = [("report_id", C.c_uint8), ("kind", C.c_uint8), ("flags", C.c_uint16),
                ("bit_offset", C.c_uint32), ("size", C.c_uint16), ("count", C.c_uint16),
                ("usage_min", C.c_uint32), ("usage_max", C.c_uint32),
                ("usage_list", C.c_uint16), ("usage_count", C.c_uint16),
                ("logical_min", C.c_int32), ("logical_max", C.c_int32),
                ("physical_min", C.c_int32), ("physical_max", C.c_int32),
                ("unit", C.c_uint32), ("unit_exp", C.c_int8), ("pad", C.c_uint8),
                ("collection", C.c_uint16), ("application", C.c_uint32)]


class Collection(C.Structure):
    _fields_ = [("usage", C.c_uint32), ("type", C.c_uint8), ("pad", C.c_uint8), ("parent", C.c_uint16)]


class Desc(C.Structure):
    _fields_ = [("field_count", C.c_uint32), ("usage_count", C.c_uint32), ("coll_count", C.c_uint32),
                ("uses_ids", C.c_uint32), ("report_bits", C.c_uint32 * (256 * 3)),
                ("fields", Field * 256), ("usages", C.c_uint32 * 1024), ("collections", Collection * 64)]


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


MOTION, BUTTON, AXIS = 2, 4, 5
KEYBOARD, POINTER = 1, 2


class Rmap(C.Structure):
    _fields_ = [(n, C.c_uint32) for n in ("dev", "uses_ids", "nfields", "nusages", "has", "led_id", "has_led",
                                         "buttons")] + [
        ("fields", Field * 12), ("usages", C.c_uint32 * 96), ("role", C.c_uint8 * 12),
        ("kbd_ids", C.c_uint8 * 32), ("ptr_ids", C.c_uint8 * 32)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


hid_parse = fn("hid_parse", C.c_int32, C.c_char_p, C.c_uint32, C.POINTER(Desc))
prepare = fn("hid_rmap_prepare", C.c_uint32, C.POINTER(Desc), C.POINTER(Rmap))
_kbd = fn("hid_rmap_keyboard", C.c_int32, C.POINTER(Rmap), C.c_char_p, C.c_uint32, C.c_void_p)
_ptr = fn("hid_rmap_pointer", C.c_int32, C.POINTER(Rmap), C.c_char_p, C.c_uint32)
input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
NOOP_OFF = C.CFUNCTYPE(C.c_uint64)(lambda: 0)
NOOP_RESTORE = C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)
C.c_void_p.in_dll(lib, "input_irq_off_fn").value = C.cast(NOOP_OFF, C.c_void_p).value
C.c_void_p.in_dll(lib, "input_irq_restore_fn").value = C.cast(NOOP_RESTORE, C.c_void_p).value
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


def prepared(rdesc, dev=5):
    d = Desc()
    assert hid_parse(rdesc, len(rdesc), C.byref(d)) == 0, "parse"
    m = Rmap(dev=dev)
    return prepare(C.byref(d), C.byref(m)), m


def kbd(m, data):
    out = (C.c_uint8 * 8)()
    rc = _kbd(C.byref(m), bytes(data), len(data), out)
    return rc, bytes(out)


def ptr(m, data):
    rc = _ptr(C.byref(m), bytes(data), len(data))
    pump()
    out = [(t, c, v) for t, c, v, d in events]
    events.clear()
    return rc, out


def nkro(mods, *usages):
    bits = 0
    for u in usages:
        bits |= 1 << u
    return bytes([1, mods]) + bits.to_bytes(15, "little")


# ---- what is found ---------------------------------------------------------------------
check("a boot-layout keyboard in report protocol", prepared(H.boot_keyboard)[0], KEYBOARD)
has, m = prepared(H.nkro_keyboard)
check("an n-key keyboard: its fields, report ID, LED report", (has, m.nfields, m.uses_ids, m.has_led, m.led_id),
      (KEYBOARD, 2, 1, 1, 1))
check("a mouse", prepared(H.mouse)[0], POINTER)
has, m = prepared(H.big_mouse)
check("a five-button mouse with a horizontal wheel", (has, m.nfields), (POINTER, 4))
check("a tablet's absolute X and Y are not a mouse", prepared(H.tablet)[0], 0)
check("media keys alone: neither", prepared(H.media)[0], 0)
check("a keyboard and a mouse in one descriptor", prepared(H.nkro_keyboard + H.big_mouse)[0], KEYBOARD | POINTER)

# ---- keyboards as boot reports -----------------------------------------------------------
_, m = prepared(H.boot_keyboard)
check("the boot layout comes back as it went", kbd(m, bytes([0x02, 0, 0x04, 0x05, 0, 0, 0, 0])),
      (1, bytes([0x02, 0, 0x04, 0x05, 0, 0, 0, 0])))
_, m = prepared(H.nkro_keyboard)
check("n-key: shift and two keys", kbd(m, nkro(0x02, 0x04, 0x16)), (1, bytes([0x02, 0, 0x04, 0x16, 0, 0, 0, 0])))
check("n-key: six keys fit", kbd(m, nkro(0, *range(4, 10)))[1], bytes([0, 0, 4, 5, 6, 7, 8, 9]))
check("n-key: seven keys are ErrorRollOver", kbd(m, nkro(0x01, *range(4, 11)))[1], bytes([0x01, 0, 1, 1, 1, 1, 1, 1]))
check("another report ID is not the keyboard's", kbd(m, bytes([2]) + bytes(16))[0], 0)
check("cut short: not a whole report", kbd(m, nkro(0, 4)[:5])[0], 0)
check("nothing held", kbd(m, nkro(0)), (1, bytes(8)))

# ---- mice -------------------------------------------------------------------------------
_, m = prepared(H.big_mouse)


def mrep(buttons=0, dx=0, dy=0, wheel=0, pan=0):
    return bytes([2, buttons]) + struct.pack("<hhbb", dx, dy, wheel, pan)


check("16-bit motion", ptr(m, mrep(dx=300, dy=-1200)), (1, [(MOTION, 300, -1200)]))
check("the back and forward buttons", ptr(m, mrep(buttons=0b11000))[1], [(BUTTON, 3, 1), (BUTTON, 4, 1)])
check("let go, left down", ptr(m, mrep(buttons=1))[1], [(BUTTON, 0, 1), (BUTTON, 3, 0), (BUTTON, 4, 0)])
check("the wheel and the horizontal wheel", ptr(m, mrep(buttons=1, wheel=1, pan=-2))[1],
      [(AXIS, 0, -1), (AXIS, 1, -2)])
check("all up", ptr(m, mrep())[1], [(BUTTON, 0, 0)])
check("cut short: ignored", ptr(m, mrep(dx=5)[:3]), (0, []))
check("another report ID: not the pointer's", ptr(m, bytes([1]) + bytes(6)), (0, []))
_, m = prepared(H.mouse)
check("a plain mouse in report protocol", ptr(m, bytes([2, 0xFB, 3, 1]))[1],
      [(MOTION, -5, 3), (AXIS, 0, -1), (BUTTON, 1, 1)])

print(f"test_report: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

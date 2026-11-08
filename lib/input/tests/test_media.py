"""Media, volume and system keys (hid/media.asm): what is kept of a report
descriptor, and reports into key events.

usage: python3 test_media.py path/to/input.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hid_gen as H  # noqa: E402

lib = C.CDLL(sys.argv[1])
KEY = 1


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


class Media(C.Structure):
    _fields_ = [("dev", C.c_uint32), ("uses_ids", C.c_uint32), ("nfields", C.c_uint32), ("nusages", C.c_uint32),
                ("fields", Field * 8), ("usages", C.c_uint32 * 64), ("down_id", C.c_uint8 * 8),
                ("down_key", C.c_uint8 * 8)]


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


hid_parse = fn("hid_parse", C.c_int32, C.c_char_p, C.c_uint32, C.POINTER(Desc))
prepare = fn("hid_media_prepare", C.c_int32, C.POINTER(Desc), C.POINTER(Media))
_report = fn("hid_media_report", None, C.POINTER(Media), C.c_char_p, C.c_uint32)
media_key = fn("hid_media_key", C.c_uint32, C.c_uint32)
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
assert C.sizeof(Field) == 52

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def prepared(rdesc, dev=7):
    d = Desc()
    assert hid_parse(rdesc, len(rdesc), C.byref(d)) == 0
    m = Media(dev=dev)
    n = prepare(C.byref(d), C.byref(m))
    return n, m


def report(m, data):
    _report(C.byref(m), bytes(data), len(data))
    pump()
    out = [(t, c, v) for t, c, v, d in events]
    devs = {d for t, c, v, d in events}
    events.clear()
    return out, devs


# ---- the table ----------------------------------------------------------------------
check("consumer and system usages → keycodes",
      [media_key(u) for u in (0x000C00E9, 0x000C00EA, 0x000C00E2, 0x000C00CD, 0x000C00B5, 0x000C00B6,
                              0x000C006F, 0x000C0070, 0x000C0223, 0x000C0192, 0x00010081, 0x00010082, 0x00010083)],
      [115, 114, 113, 164, 163, 165, 225, 224, 172, 140, 116, 142, 143])
check("nothing for others", [media_key(u) for u in (0x000C0001, 0x000C03FF, 0x00070004, 0x00010030)], [0, 0, 0, 0])

# ---- what is kept ---------------------------------------------------------------------
n, m = prepared(H.media)
check("three input fields kept, no padding, report IDs on",
      (n, m.nfields, [m.fields[i].report_id for i in range(n)], m.uses_ids, m.dev), (3, 3, [2, 3, 4], 1, 7))
check("the listed usages copied with the field", (m.nusages, list(m.usages[:4]), m.fields[1].usage_list),
      (4, [0x000C00E9, 0x000C00EA, 0x000C00E2, 0x000C00CD], 0))
check("a keyboard alone has none", prepared(H.boot_keyboard)[0], 0)
check("a mouse alone has none", prepared(H.mouse)[0], 0)
n, m = prepared(H.boot_keyboard + H.media)
check("with a keyboard collection before it: only the media fields", n, 3)

# ---- reports ---------------------------------------------------------------------------
n, m = prepared(H.media)
check("volume up from the array report", report(m, b"\x02" + struct.pack("<HH", 0xE9, 0)),
      ([(KEY, 115, 1)], {7}))
check("held while mute joins it", report(m, b"\x02" + struct.pack("<HH", 0xE9, 0xE2))[0], [(KEY, 113, 1)])
check("both up", report(m, b"\x02" + struct.pack("<HH", 0, 0))[0], [(KEY, 115, 0), (KEY, 113, 0)])
check("the bit report: play/pause", report(m, b"\x03\x08")[0], [(KEY, 164, 1)])
check("another report ID leaves it held", report(m, b"\x02" + struct.pack("<HH", 0xB5, 0))[0], [(KEY, 163, 1)])
check("the bit report changes only its own keys", report(m, b"\x03\x01")[0], [(KEY, 164, 0), (KEY, 115, 1)])
check("system control: sleep (value 2)", report(m, b"\x04\x02")[0], [(KEY, 142, 1)])
check("and up", report(m, b"\x04\x00")[0], [(KEY, 142, 0)])
before = C.c_uint32.in_dll(lib, "hid_media_unknown").value
check("a usage with no key: counted, nothing sent",
      (report(m, b"\x02" + struct.pack("<HH", 0xB5, 0x123))[0], C.c_uint32.in_dll(lib, "hid_media_unknown").value - before),
      ([], 1))
check("an unknown report ID: nothing", report(m, b"\x09\xFF\xFF")[0], [])
check("a report cut short changes nothing (next track stays held)", (report(m, b"\x02\x00")[0], 163 in list(m.down_key)),
      ([], True))
check("an empty report", report(m, b"")[0], [])
report(m, b"\x02" + struct.pack("<HH", 0, 0))
report(m, b"\x03\x00")
check("all up at the end", list(m.down_key), [0] * 8)

print(f"test_media: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

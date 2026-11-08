"""The driver table (core/match.asm), policy settings (core/conf.asm), and
keyboards and mice in report protocol through class/hid.

usage: python3 test_match.py path/to/usb.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import devices as D  # noqa: E402
import xhci_sim as X  # noqa: E402

G, H = D.G, D.H
lib = C.CDLL(sys.argv[1])
KEY, MOTION, BUTTON, AXIS, DEVICE = 1, 2, 4, 5, 10
EINVAL, ENOMEM = -11, -8
SHOW, ACCEPTED = 1, 2


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


attach = fn("xhci_attach", C.c_void_p, C.c_void_p)
scan = fn("usb_scan", C.c_int32, C.c_void_p)
device_get = fn("usb_device_get", C.c_void_p, C.c_uint32)
attach_drivers = fn("usb_attach_drivers", C.c_int32, C.c_void_p)
register_driver = fn("usb_driver_register", C.c_int32, C.c_void_p)
matches = fn("usb_driver_matches", C.c_int32, C.c_void_p, C.c_void_p)
conf_apply = fn("usb_conf_apply", C.c_int32, C.c_char_p, C.c_uint32)
hid_service = fn("usb_hid_service", C.c_int32)
poll = fn("xhci_poll", C.c_int32, C.c_void_p)
input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
dev_info = fn("ut_input_device_info", C.c_int64, C.c_uint32)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731

ARENA = C.create_string_buffer(16 << 20)
arena = [C.addressof(ARENA)]


def alloc(size, align):
    p = (arena[0] + align - 1) & ~(align - 1)
    arena[0] = p + size
    return p


sim = None
auth = []
hooks = [C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(alloc),
         C.CFUNCTYPE(None, C.c_uint64)(lambda us: None),
         C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: sim.read(a) & 0xFFFFFFFF),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: sim.write(a, v)),
         C.CFUNCTYPE(C.c_uint64)(lambda: 0), C.CFUNCTYPE(None, C.c_uint64)(lambda f: None),
         C.CFUNCTYPE(None, C.c_uint32, C.c_uint32, C.c_uint64)(lambda e, v, d: auth.append((e, v)))]
for name, cb in zip(("usb_alloc_fn", "usb_delay_fn", "usb_rd32_fn", "usb_wr32_fn", "input_irq_off_fn",
                     "input_irq_restore_fn", "usb_keyboard_auth_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class Driver(C.Structure):
    _fields_ = [("match", C.c_uint16), ("vendor", C.c_uint16), ("product", C.c_uint16), ("cls", C.c_uint8),
                ("subclass", C.c_uint8), ("protocol", C.c_uint8), ("pad", C.c_uint8 * 7),
                ("attach", C.c_void_p), ("name", C.c_char_p)]


assert C.sizeof(Driver) == 32
events = []
on_event = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)(
    lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                Event.from_address(e).value, Event.from_address(e).device)))


def fresh():
    global sim
    sim = X.XhciSim()
    for n in ("xhci_hc_count", "usb_device_total", "usb_hid_count", "usb_hub_count", "usb_driver_count"):
        u32(n).value = 0
    u32("usb_hid_trusting").value = 1
    u32("usb_new_keyboard_check").value = 1
    input_init()
    register(C.cast(on_event, C.c_void_p), 0)
    events.clear()
    auth.clear()
    return attach(sim.base)


def take(hc):
    for _ in range(3):
        sim.pump()
        poll(hc)
        hid_service()
    pump()
    out = [e for e in events if e[0] != DEVICE]
    events.clear()
    return out


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# ---- settings -----------------------------------------------------------------------
def apply(text, start=1):
    u32("usb_new_keyboard_check").value = start
    before = u32("usb_conf_rejected").value
    n = conf_apply(text, len(text))
    return n, u32("usb_new_keyboard_check").value, u32("usb_conf_rejected").value - before


check("off", apply(b"new_keyboard_check = off\n"), (1, 0, 0))
check("comments, case, no spaces, CRLF", apply(b"# USB policy\r\n\r\nNEW_KEYBOARD_CHECK=On  \r\n", 0), (1, 1, 0))
check("yes/no/true/false/1/0", [apply(b"new_keyboard_check = " + w)[1] for w in (b"no", b"false", b"0")] +
      [apply(b"new_keyboard_check = " + w, 0)[1] for w in (b"yes", b"true", b"1")], [0, 0, 0, 1, 1, 1])
check("a comment after the value", apply(b"new_keyboard_check = off   # for the lab\n"), (1, 0, 0))
check("a value it does not know: rejected, nothing changed", apply(b"new_keyboard_check = maybe\n"), (0, 1, 1))
check("no '=': rejected", apply(b"new_keyboard_check off\n"), (0, 1, 1))
check("an unknown name: rejected", apply(b"new_keyboard = off\n"), (0, 1, 1))
check("no newline at the end, tabs", apply(b"\tnew_keyboard_check\t=\toff"), (1, 0, 0))
check("the last one wins", apply(b"new_keyboard_check = off\nnew_keyboard_check = on\n", 0), (2, 1, 0))
check("empty", apply(b""), (0, 1, 0))

# ---- the driver table ------------------------------------------------------------------
hc = fresh()
kbd = D.keyboard()
sim.attach(1, kbd)
scan(hc)
dev = device_get(0)
taken = []
TAKE = C.CFUNCTYPE(C.c_int32, C.c_void_p)(lambda d: (taken.append("vendor"), 1)[1])
DECLINE = C.CFUNCTYPE(C.c_int32, C.c_void_p)(lambda d: (taken.append("decline"), 0)[1])
by_id = Driver(match=3, vendor=0x046D, product=0xC31C, attach=C.cast(TAKE, C.c_void_p).value, name=b"vendor")
other = Driver(match=3, vendor=0x1234, product=0x5678, attach=C.cast(TAKE, C.c_void_p).value)
by_if = Driver(match=8 | 16 | 32, cls=3, subclass=1, protocol=1, attach=C.cast(DECLINE, C.c_void_p).value)
check("matching: vendor and product", [matches(C.byref(d), dev) for d in (by_id, other)], [1, 0])
check("matching: interface class, subclass, protocol", (matches(C.byref(by_if), dev),
                                                        matches(C.byref(Driver(match=8 | 32, cls=3, protocol=2)), dev)),
      (1, 0))
check("matching: device class", (matches(C.byref(Driver(match=4, cls=0)), dev), matches(C.byref(Driver(match=4, cls=9)), dev)),
      (1, 0))
check("no attach function: refused", register_driver(C.byref(Driver(match=1))), EINVAL)
check("registered", (register_driver(C.byref(by_if)), register_driver(C.byref(by_id))), (0, 0))
check("tried in order; one that declines passes it on; a registered one before the built-in HID",
      (attach_drivers(dev), taken, u32("usb_hid_count").value), (1, ["decline", "vendor"], 0))
u32("usb_driver_count").value = 0
spare = [Driver(match=1, vendor=1, attach=C.cast(TAKE, C.c_void_p).value) for _ in range(17)]
check("sixteen at most", [register_driver(C.byref(d)) for d in spare][-2:], [0, ENOMEM])
u32("usb_driver_count").value = 0
taken.clear()
check("with none registered, the built-in HID driver", (attach_drivers(dev), taken, u32("usb_hid_count").value),
      (1, [], 1))


# ---- a mouse in report protocol -------------------------------------------------------
def report_mouse(rdesc):
    cfg = G.config(G.interface(0, num_ep=1, cls=3, sub=1, proto=2), G.hid(len(rdesc)), G.endpoint(0x81, 3, 8, 1))
    d = D.Device(G.device(vid=0x046D, pid=0xC08B, mps0=64, manufacturer=0, product=1, serial=0), cfg, {1: "G502"})
    d.report_descs = {0: rdesc}
    return d


hc = fresh()
gm = report_mouse(H.big_mouse)
sim.attach(1, gm)
scan(hc)
check("taken", attach_drivers(device_get(0)), 1)
check("report protocol asked for", [r[2] for r in gm.requests if r[1] == 0x0B], [1])
check("a mouse in lib/input", (C.c_char_p.from_address(dev_info(1) + 8).value, C.c_uint64.from_address(dev_info(1) + 32).value),
      (b"USB mouse", 2))
gm.queue(0x81, bytes([2, 0b10001]) + struct.pack("<hhbb", 400, -30, 1, 2))
gm.queue(0x81, bytes([2, 0]) + struct.pack("<hhbb", 0, 0, 0, 0))
check("wide motion, the wheels, buttons 1 and 5", take(hc),
      [(MOTION, 400, -30, 1), (AXIS, 0, -1, 1), (AXIS, 1, 2, 1), (BUTTON, 0, 1, 1), (BUTTON, 4, 1, 1),
       (BUTTON, 0, 0, 1), (BUTTON, 4, 0, 1)])
hc = fresh()
bad = report_mouse(b"\x05")
sim.attach(1, bad)
scan(hc)
attach_drivers(device_get(0))
check("a descriptor that does not parse: boot protocol", [r[2] for r in bad.requests if r[1] == 0x0B], [0])
bad.queue(0x81, bytes([1, 2, 3, 0]))
check("and boot reports", take(hc), [(MOTION, 2, 3, 1), (BUTTON, 0, 1, 1)])


# ---- a keyboard with no boot interface: n-key reports, LEDs in report 1 ------------------
def nkro_keyboard():
    cfg = G.config(G.interface(0, num_ep=1, cls=3, sub=0, proto=0), G.hid(len(H.nkro_keyboard)),
                   G.endpoint(0x81, 3, 32, 1))                 # a 17-byte report
    d = D.Device(G.device(vid=0x1532, pid=0x0203, mps0=64, manufacturer=0, product=1, serial=0), cfg, {1: "NKRO"})
    d.report_descs = {0: H.nkro_keyboard}
    return d


def nk(mods, *usages):
    bits = 0
    for u in usages:
        bits |= 1 << u
    return bytes([1, mods]) + bits.to_bytes(15, "little")


hc = fresh()
k = nkro_keyboard()
sim.attach(1, k)
scan(hc)
check("taken as a keyboard", (attach_drivers(device_get(0)), C.c_char_p.from_address(dev_info(1) + 8).value,
                              C.c_uint64.from_address(dev_info(1) + 32).value), (1, b"USB keyboard", 1))
check("no boot protocol asked of it", [r for r in k.requests if r[1] == 0x0B], [])
k.queue(0x81, nk(0x02, 0x0B))
k.queue(0x81, nk(0x02, 0x0B, 0x0C))
k.queue(0x81, nk(0))
check("shift, h, i, all up (keys before modifiers)", take(hc),
      [(KEY, 42, 1, 1), (KEY, 35, 1, 1), (KEY, 23, 1, 1), (KEY, 35, 0, 1), (KEY, 23, 0, 1), (KEY, 42, 0, 1)])
k.queue(0x81, nk(0, 0x39))
k.queue(0x81, nk(0))
take(hc)
check("Caps Lock: the LED report with its ID", (k.leds, [r[2] for r in k.requests if r[:2] == (0x21, 0x09)]), ([1], [0x0201]))
k.queue(0x81, nk(0, *range(4, 12)))
check("more keys than six: ignored as rollover", take(hc), [])

hc = fresh()
u32("usb_hid_trusting").value = 0
k2 = nkro_keyboard()
sim.attach(1, k2)
scan(hc)
attach_drivers(device_get(0))
code = str([v for e, v in auth if e == SHOW][-1])
for ch in code:
    k2.queue(0x81, nk(0, 0x27 if ch == "0" else 0x1D + int(ch)))
    k2.queue(0x81, nk(0))
k2.queue(0x81, nk(0, 0x28))                               # Enter
k2.queue(0x81, nk(0))
check("its code typed as n-key reports: nothing through, then accepted", (take(hc), auth[-1][0]), ([], ACCEPTED))
k2.queue(0x81, nk(0, 0x04))
check("and it types", take(hc), [(KEY, 30, 1, 1)])

print(f"test_match: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

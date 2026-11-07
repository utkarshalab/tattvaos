"""USB keyboards and mice (class/hid) end to end: the simulated controller,
enumeration, configuration, interrupt transfers, lib/input events.

usage: python3 test_hid.py path/to/usb.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import devices as D  # noqa: E402
import xhci_sim as X  # noqa: E402

lib = C.CDLL(sys.argv[1])
KEY, MOTION, BUTTON = 1, 2, 4


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


attach = fn("xhci_attach", C.c_void_p, C.c_void_p)
scan = fn("usb_scan", C.c_int32, C.c_void_p)
device_get = fn("usb_device_get", C.c_void_p, C.c_uint32)
hid_attach = fn("usb_hid_attach", C.c_int32, C.c_void_p)
hid_service = fn("usb_hid_service", C.c_int32)
poll = fn("xhci_poll", C.c_int32, C.c_void_p)
configure = fn("xhci_configure_iface", C.c_int32, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32)
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
hooks = [C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(alloc),
         C.CFUNCTYPE(None, C.c_uint64)(lambda us: None),
         C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: sim.read(a) & 0xFFFFFFFF),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: sim.write(a, v)),
         C.CFUNCTYPE(C.c_uint64)(lambda: 0), C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)]
for name, cb in zip(("usb_alloc_fn", "usb_delay_fn", "usb_rd32_fn", "usb_wr32_fn", "input_irq_off_fn",
                     "input_irq_restore_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class DevInfo(C.Structure):
    _fields_ = [("id", C.c_uint32), ("pad0", C.c_uint32), ("name", C.c_char_p), ("bus", C.c_uint32),
                ("vendor", C.c_uint16), ("product", C.c_uint16), ("version", C.c_uint16),
                ("pad1", C.c_uint16 * 3), ("caps", C.c_uint64)]


events = []
on_event = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)(
    lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                Event.from_address(e).value, Event.from_address(e).device)))


def fresh():
    global sim
    sim = X.XhciSim()
    for n in ("xhci_hc_count", "usb_device_total", "usb_hid_count"):
        u32(n).value = 0
    input_init()
    register(C.cast(on_event, C.c_void_p), 0)
    events.clear()
    return attach(sim.base)


def take(hc):
    """Let the devices send what they have, then collect the events."""
    sim.pump()
    poll(hc)
    pump()
    out = events[:]
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


def kreport(mods=0, *keys):
    return bytes([mods, 0] + list(keys) + [0] * (6 - len(keys)))


# ---- a keyboard and a mouse ------------------------------------------------------------
hc = fresh()
kbd, ms, bt = D.keyboard(), D.mouse(), D.bluetooth()
sim.attach(1, kbd)
sim.attach(2, ms)
sim.attach(3, bt)
check("enumerated", scan(hc), 3)
claimed = [hid_attach(device_get(i)) for i in range(3)]
check("the keyboard and mouse claimed, the radio not", claimed, [1, 1, 0])
check("configured, boot protocol, no idle repeat",
      [(d.configuration, d.protocol, d.idle) for d in (kbd, ms)], [(1, 0, 0), (1, 0, 0)])
check("the radio left unconfigured", bt.configuration, 0)
k_ep = sim.slots[1].eps[3]
m_ep = sim.slots[2].eps[3]
check("endpoint contexts: interrupt IN, packet size, interval (10 ms → 2^6 × 125 µs)",
      [((e.ctx[1] >> 3) & 7, e.ctx[1] >> 16, (e.ctx[0] >> 16) & 0xFF, (e.ctx[1] >> 1) & 3) for e in (k_ep, m_ep)],
      [(7, 8, 6, 3), (7, 4, 6, 3)])
check("max ESIT payload and context entries", (k_ep.ctx[2] >> 16, sim.slots[1].entries), (8, 3))
ids = [u32("usb_hid_count").value]
infos = [DevInfo.from_address(dev_info(i)) for i in (1, 2)]
check("input devices", [(i.name, i.bus, i.vendor, i.product, i.caps) for i in infos],
      [(b"USB keyboard", 3, 0x046D, 0xC31C, 1), (b"USB mouse", 3, 0x1BCF, 0x0005, 2)])

kbd.queue(0x81, kreport(0, 0x0B))                       # h
kbd.queue(0x81, kreport(0, 0x0B, 0x0C))                 # i
kbd.queue(0x81, kreport(0))
check("typing: h, i, both up", take(hc),
      [(KEY, 35, 1, 1), (KEY, 23, 1, 1), (KEY, 35, 0, 1), (KEY, 23, 0, 1)])
ms.queue(0x81, bytes([1, 10, 0xF6, 0]))
ms.queue(0x81, bytes([0, 0, 0, 1]))
check("the mouse: motion and a click, then the wheel", take(hc),
      [(MOTION, 10, -10, 2), (BUTTON, 0, 1, 2), (5, 0, -1, 2), (BUTTON, 0, 0, 2)])
check("nothing queued: nothing", take(hc), [])
reports = [e for e in sim.log if e[0] == "stream"]
check("reports read, transfers put back each time", (len(reports), all(e[3] in (8, 4) for e in reports)), (5, True))

# Caps Lock: the LED report goes out from the service, not the completion
kbd.queue(0x81, kreport(0, 0x39))
take(hc)
check("no LED report inside the completion", kbd.leds, [])
check("the service sends it", (hid_service(), kbd.leds), (1, [2]))
check("and then has nothing to do", hid_service(), 0)
kbd.queue(0x81, kreport(0))
take(hc)

# a stall on the interrupt endpoint: recovered by the service
kbd.queue(0x81, "stall")
kbd.queue(0x81, kreport(0, 0x04))
take(hc)
check("stalled: no events yet", take(hc), [])
check("recovered", (hid_service(), [e[0] for e in sim.log if e[0] in ("reset_ep", "set_deq")][-2:]),
      (1, ["reset_ep", "set_deq"]))
check("and reading again", take(hc), [(KEY, 30, 1, 1)])

# a babbling report (longer than asked for)
kbd.queue(0x81, bytes(16))
take(hc)
hid_service()
kbd.queue(0x81, kreport(0))
check("babble: recovered too", take(hc), [(KEY, 30, 0, 1)])

# unplugged
sim.detach(1)
take(hc)
for _ in range(12):
    hid_service()
    take(hc)
hid = C.c_uint64.from_address(C.addressof(C.c_uint64.in_dll(lib, "usb_hids"))).value
flags = C.c_uint32.from_address(hid + 8 + 12).value
check("gone: given up on after the errors", flags & 4, 4)
ms.queue(0x81, bytes([2, 0, 0, 0]))
check("the mouse carries on", take(hc), [(BUTTON, 1, 1, 2)])

# a keyboard that refuses SET_PROTOCOL and SET_IDLE still works
hc = fresh()
k2 = D.keyboard()
k2.class_stalls = {0x0A, 0x0B}
sim.attach(1, k2)
scan(hc)
check("refused boot requests: claimed anyway", hid_attach(device_get(0)), 1)
k2.queue(0x81, kreport(0x01, 0x06))
check("ctrl-c", take(hc), [(KEY, 29, 1, 1), (KEY, 46, 1, 1)])

# endpoint contexts at other speeds and types
hc = fresh()
disk, radio = D.superspeed_disk(), D.bluetooth()
sim.attach(3, disk)
sim.attach(1, radio)
scan(hc)
d0, dss = device_get(0), device_get(1)                  # by port: the radio, then the disk
check("which is which", (C.c_uint8.from_address(d0 + 19).value, C.c_uint8.from_address(dss + 19).value), (3, 4))
slot_ss = C.c_uint8.from_address(dss + 16).value
slot_hs = C.c_uint8.from_address(d0 + 16).value
cfg = C.c_uint64.from_address(dss + 56).value
check("SuperSpeed bulk", configure(hc, slot_ss, cfg, 0), 0)
e_in, e_out = sim.slots[slot_ss].eps[3], sim.slots[slot_ss].eps[4]
check("bulk IN and OUT: types, 1024 bytes, burst 15, no interval",
      [((e.ctx[1] >> 3) & 7, e.ctx[1] >> 16, (e.ctx[1] >> 8) & 0xFF, (e.ctx[0] >> 16) & 0xFF) for e in (e_in, e_out)],
      [(6, 1024, 15, 0), (2, 1024, 15, 0)])
cfg = C.c_uint64.from_address(d0 + 56).value
check("high-speed radio: interface 0", configure(hc, slot_hs, cfg, 0), 0)
ev = sim.slots[slot_hs].eps[3]
check("its event endpoint: interrupt IN, 2^(4-1) microframes", ((ev.ctx[1] >> 3) & 7, (ev.ctx[0] >> 16) & 0xFF), (7, 3))
check("voice, alternate setting 1: isochronous, no error count",
      (configure(hc, slot_hs, cfg, 2), [((sim.slots[slot_hs].eps[d].ctx[1] >> 3) & 7,
                                         (sim.slots[slot_hs].eps[d].ctx[1] >> 1) & 3) for d in (7, 6)]),
      (0, [(5, 0), (1, 0)]))
check("an interface that is not there", configure(hc, slot_hs, cfg, 9), -11)

print(f"test_hid: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

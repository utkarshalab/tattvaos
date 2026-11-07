"""Hubs (class/hub), removal and the new-keyboard check (class/hid), against
the simulated controller and hubs.

usage: python3 test_hub.py path/to/usb.so
"""
import ctypes as C
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import devices as D  # noqa: E402
import xhci_sim as X  # noqa: E402

lib = C.CDLL(sys.argv[1])
KEY, MOTION, BUTTON, DEVICE = 1, 2, 4, 10
SHOW, ACCEPTED, WRONG, REFUSED = 1, 2, 3, 4


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


attach = fn("xhci_attach", C.c_void_p, C.c_void_p)
scan = fn("usb_scan", C.c_int32, C.c_void_p)
device_get = fn("usb_device_get", C.c_void_p, C.c_uint32)
attach_drivers = fn("usb_attach_drivers", C.c_int32, C.c_void_p)
remove = fn("usb_device_remove", None, C.c_void_p)
hub_service = fn("usb_hub_service", C.c_int32)
hid_service = fn("usb_hid_service", C.c_int32)
poll = fn("xhci_poll", C.c_int32, C.c_void_p)
input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
dev_info = fn("ut_input_device_info", C.c_int64, C.c_uint32)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731

# memory, with every block accounted for
ARENA = C.create_string_buffer(32 << 20)
arena = {"next": C.addressof(ARENA)}
live = {}


def alloc(size, align):
    p = (arena["next"] + align - 1) & ~(align - 1)
    arena["next"] = p + size
    live[p] = size
    return p


def free(p, size, align):
    assert p in live, hex(p)
    assert live.pop(p) == size, "freed with another size"


sim = None
auth = []
hooks = [C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(alloc),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint64, C.c_uint64)(free),
         C.CFUNCTYPE(None, C.c_uint64)(lambda us: None),
         C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: sim.read(a) & 0xFFFFFFFF),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: sim.write(a, v)),
         C.CFUNCTYPE(C.c_uint64)(lambda: 0), C.CFUNCTYPE(None, C.c_uint64)(lambda f: None),
         C.CFUNCTYPE(None, C.c_uint32, C.c_uint32, C.c_uint64)(lambda e, v, d: auth.append((e, v)))]
for name, cb in zip(("usb_alloc_fn", "usb_free_fn", "usb_delay_fn", "usb_rd32_fn", "usb_wr32_fn",
                     "input_irq_off_fn", "input_irq_restore_fn", "usb_keyboard_auth_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


class UsbDevice(C.Structure):
    _fields_ = [("hc", C.c_uint64), ("parent", C.c_uint64), ("slot", C.c_uint8), ("port", C.c_uint8),
                ("root_port", C.c_uint8), ("speed", C.c_uint8), ("route", C.c_uint32), ("depth", C.c_uint8),
                ("address", C.c_uint8), ("state", C.c_uint8), ("config_value", C.c_uint8),
                ("max_packet0", C.c_uint16), ("flags", C.c_uint16), ("desc", C.c_uint8 * 18),
                ("config_len", C.c_uint16), ("tt", C.c_uint32), ("config", C.c_uint64),
                ("config_raw", C.c_uint64), ("driver", C.c_uint64), ("driver_data", C.c_uint64)]


events = []
on_event = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)(
    lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                Event.from_address(e).value, Event.from_address(e).device)))


def fresh(**kw):
    global sim
    sim = X.XhciSim(**kw)
    for n in ("xhci_hc_count", "usb_device_total", "usb_hid_count", "usb_hub_count"):
        u32(n).value = 0
    u32("usb_hid_trusting").value = 1
    input_init()
    register(C.cast(on_event, C.c_void_p), 0)
    events.clear()
    auth.clear()
    return attach(sim.base)


def devices():
    return [UsbDevice.from_address(device_get(i)) for i in range(u32("usb_device_total").value)]


def find(vid_pid, route=None):
    for d in devices():
        vp = (d.desc[8] | d.desc[9] << 8, d.desc[10] | d.desc[11] << 8)
        if vp == vid_pid and (route is None or d.route == route):
            return d
    return None


def settle(hc, rounds=4):
    """The fiber, a few turns: reports, hubs' ports, drivers' work."""
    for _ in range(rounds):
        sim.pump()
        poll(hc)
        hub_service()
        hid_service()
    pump()


def take(hc):
    settle(hc)
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


KBD, MOUSE, RADIO, DISK = (0x046D, 0xC31C), (0x1BCF, 0x0005), (0x0E8D, 0x0608), (0x0781, 0x5583)
HUB2, HUB3 = (0x05E3, 0x0610), (0x05E3, 0x0626)

# ---- a USB 2 hub and a USB 3 hub, devices of every speed behind them --------------
hc = fresh(usb2_ports=2, usb3_ports=2)
h2 = D.Hub(ports=4)
h3 = D.Hub(ports=4, superspeed=True, untrained={4})
kbd, ms, radio, disk, disk2 = D.keyboard(), D.mouse(), D.bluetooth(), D.superspeed_disk(), D.superspeed_disk()
ms.speed = D.SPEED_LOW
ms.device_desc = D.G.device(vid=0x1BCF, pid=0x0005, mps0=8, manufacturer=0, product=1, serial=0)
h2.attach(1, kbd)
h2.attach(2, radio)
h2.attach(3, ms)
h3.attach(2, disk)
h3.attach(4, disk2)
sim.attach(1, h2)
sim.attach(3, h3)
check("the hubs on root ports", scan(hc), 2)
check("both taken as hubs", [attach_drivers(device_get(i)) for i in range(2)], [1, 1])
check("ports powered, USB 3 hub given its depth",
      ([p.powered for p in h2.hub_ports + h3.hub_ports], h3.depth), ([True] * 8, 0))
s2 = find(HUB2).slot
s3 = find(HUB3).slot
check("the controller told they are hubs: ports, TT think time, multi-TT",
      (sim.slots[s2].hub, sim.slots[s3].hub), ((1, 0, 4, 1), (1, 0, 4, 0)))
settle(hc)
check("everything behind them enumerated", len(devices()), 7)
k, m, r, d1, d2 = find(KBD), find(MOUSE), find(RADIO), find(DISK, 2), find(DISK, 4)
check("speeds", [x.speed for x in (k, m, r, d1, d2)], [1, 2, 3, 4, 4])
check("route strings: the port on the hub", [x.route for x in (k, m, r, d1, d2)], [1, 3, 2, 2, 4])
check("one tier down, the root port of the hub", ({x.depth for x in (k, m, r, d1)}, {x.root_port for x in (k, m, r)},
                                                 d1.root_port), ({1}, {1}, 3))
check("full and low speed through the hub's TT; high speed and SuperSpeed need none",
      [x.tt for x in (k, m, r, d1)], [s2 | (1 << 8), s2 | (3 << 8), 0, 0])
check("the controller got them", [e[2:] for e in sim.log if e[0] == "tt" and e[1] in (k.slot, m.slot)],
      [(s2 | (1 << 8), 0), (s2 | (3 << 8), 0)])
check("USB 2 ports reset; the untrained USB 3 port warm reset, the other left as trained",
      ([p.resets for p in h2.hub_ports[:3]], [p.warm for p in h3.hub_ports], h3.hub_ports[1].resets),
      ([1, 1, 1], [0, 0, 0, 1], 0))
check("change bits all cleared", [p.change for p in h2.hub_ports + h3.hub_ports], [0] * 8)
adds = [e for e in take(hc) if e[0] == DEVICE]
check("the keyboard and mouse arrived in lib/input", [(e[1], e[2]) for e in adds], [(0, 1), (0, 2)])
kbd.queue(0x81, kreport(0, 0x04))
ms.queue(0x81, bytes([0, 3, 4, 0]))
check("typing and moving through the hub", take(hc), [(KEY, 30, 1, 1), (MOTION, 3, 4, 2)])

# ---- unplugged and plugged back in behind the hub ---------------------------------
kslot = k.slot
h2.detach(1)
ev = take(hc)
check("gone from the hub: its input device too", ([e for e in ev if e[0] == DEVICE], len(devices()),
                                                  find(KBD) is None), ([(DEVICE, 1, 0, 1)], 6, True))
check("its slot disabled", [e for e in sim.log if e[0] == "cmd" and e[1] == 10][-1][2], kslot)
kbd2 = D.keyboard()
h2.attach(4, kbd2)
ev = take(hc)
k = find(KBD)
check("on another port", (k.route, [e for e in ev if e[0] == DEVICE]), (4, [(DEVICE, 0, 1, 1)]))
kbd2.queue(0x81, kreport(0, 0x05))
check("and types", take(hc), [(KEY, 48, 1, 1)])
leaked = 0
for i in range(50):
    h2.detach(4)
    settle(hc)
    if i == 0:
        base = dict(live)
    h2.attach(4, D.keyboard())
    settle(hc)
    h2.detach(4)
    settle(hc)
    leaked = max(leaked, len(live) - len(base), sum(live.values()) - sum(base.values()))
    h2.attach(4, D.keyboard())
    settle(hc)
check("50 times out and in: nothing kept", leaked, 0)
events.clear()

# ---- a hub behind a hub -----------------------------------------------------------
h2.detach(4)
settle(hc)
inner = D.Hub(ports=4, multi_tt=True)
kbd3 = D.keyboard()
inner.attach(2, kbd3)
h2.attach(4, inner)
settle(hc)
ki = find(KBD)
si = find(HUB2, 4).slot
check("two tiers: route, depth, the nearest high-speed hub's TT (multi-TT)",
      (ki.route, ki.depth, ki.tt, sim.slots[si].hub), (0x24, 2, si | (2 << 8) | (1 << 16), (1, 1, 4, 1)))
events.clear()
kbd3.queue(0x81, kreport(0, 0x06))
check("types from two hubs down", [e for e in take(hc) if e[0] == KEY], [(KEY, 46, 1, 1)])

# ---- over-current -------------------------------------------------------------------
h2.over_current(2)
settle(hc)
hub_rec = C.c_uint64.from_address(C.addressof(C.c_uint64.in_dll(lib, "usb_hubs"))).value
check("over-current counted and cleared", (C.c_uint32.from_address(hub_rec + 28).value, h2.hub_ports[1].change),
      (1, 0))

# ---- the whole USB 2 tree pulled out at the root ------------------------------------
events.clear()
remove(C.c_void_p(C.addressof(find(HUB2, 0))))
ev = [e for e in take(hc) if e[0] == DEVICE]
check("everything behind it went too", (sorted(e[3] for e in ev), [e[1] for e in ev], len(devices()),
                                        u32("usb_hub_count").value), ([1, 2], [1, 1], 3, 1))

# ---- five tiers at most -------------------------------------------------------------
hc = fresh(usb2_ports=2, usb3_ports=0)
chain = [D.Hub(ports=2) for _ in range(6)]
for a, b in zip(chain, chain[1:]):
    a.attach(1, b)
chain[-1].attach(1, D.keyboard())
sim.attach(1, chain[0])
scan(hc)
attach_drivers(device_get(0))
settle(hc, rounds=10)
check("hubs at tiers 1-5 work; a sixth tier is not used as a hub",
      (u32("usb_hub_count").value, max(d.depth for d in devices()), find(KBD) is None), (5, 5, True))

# ---- the new-keyboard check ---------------------------------------------------------
hc = fresh()
hub = D.Hub(ports=4)
sim.attach(1, hub)
scan(hc)
attach_drivers(device_get(0))
settle(hc)
u32("usb_hid_trusting").value = 0                 # start-up is over
nk = D.keyboard()
hub.attach(1, nk)
nm = D.mouse()
hub.attach(2, nm)
ev = take(hc)
shown = [v for e, v in auth if e == SHOW]
check("a code shown for the keyboard, not for the mouse", (len(shown), 100000 <= shown[0] <= 999999), (1, True))
check("only the mouse in lib/input yet", [e for e in ev if e[0] == DEVICE], [(DEVICE, 0, 2, 1)])
code = str(shown[0])
USAGE = {str(n): 0x1D + n for n in range(1, 10)} | {"0": 0x27}
KEYPAD = {str(n): 0x58 + n for n in range(1, 10)} | {"0": 0x62}


def type_on(dev, text, table=USAGE, enter=0x28):
    for ch in text:
        dev.queue(0x81, kreport(0, table[ch]))
        dev.queue(0x81, kreport(0))
    dev.queue(0x81, kreport(0, enter))
    dev.queue(0x81, kreport(0))


wrong = "1" + code[1:] if code[0] != "1" else "2" + code[1:]
type_on(nk, wrong)
check("typing while held back: no keys reach lib/input", [e for e in take(hc) if e[0] == KEY], [])
check("a wrong code: two tries left", auth[-1], (WRONG, 2))
nk.queue(0x81, kreport(0, USAGE["9"]))
nk.queue(0x81, kreport(0))
nk.queue(0x81, kreport(0, 0x2A))                   # Backspace: start again
nk.queue(0x81, kreport(0))
type_on(nk, code, KEYPAD, enter=0x58)
ev = take(hc)
check("the right code on the keypad, after a Backspace: accepted",
      (auth[-1], [e for e in ev if e[0] == DEVICE], [e for e in ev if e[0] == KEY]),
      ((ACCEPTED, 0), [(DEVICE, 0, 1, 2)], []))
nk.queue(0x81, kreport(0, 0x0B))
check("and it types", take(hc), [(KEY, 35, 1, 2)])

bad = D.keyboard()
hub.attach(3, bad)
settle(hc)
for _ in range(3):
    type_on(bad, "000000" if code != "000000" else "111111")
ev = take(hc)
check("three wrong codes: refused", ([e for e, v in auth[-4:]], [e for e in ev if e[0] in (KEY, DEVICE)]),
      ([SHOW, WRONG, WRONG, REFUSED], []))
bad.queue(0x81, kreport(0, 0x04))
check("refused stays refused", take(hc), [])
hub.detach(3)
settle(hc)
hub.attach(3, D.keyboard())
settle(hc)
check("unplugged and back: a new code", [e for e, v in auth[-1:]], [SHOW])
hub.detach(3)
ev = take(hc)
check("pulled out while held back: never in lib/input, nothing to remove", [e for e in ev if e[0] == DEVICE], [])
u32("usb_new_keyboard_check").value = 0
n0 = len(auth)
hub.attach(3, D.keyboard())
check("with the check off: straight in", (len(auth) - n0, [e[:2] for e in take(hc) if e[0] == DEVICE]),
      (0, [(DEVICE, 0)]))
u32("usb_new_keyboard_check").value = 1

print(f"test_hub: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

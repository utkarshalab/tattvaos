"""The xHCI driver and enumeration against the software controller in sim/.

usage: python3 test_xhci.py path/to/usb.so
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
ESTALL, ETIMEOUT, ENODEV, EHC = -4, -5, -7, -9
FAIL_NOMEM, FAIL_RESET = 1, 3


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


attach = fn("xhci_attach", C.c_void_p, C.c_void_p)
portsc = fn("xhci_portsc", C.c_uint32, C.c_void_p, C.c_uint32)
port_reset = fn("xhci_port_reset", C.c_int32, C.c_void_p, C.c_uint32)
command = fn("xhci_command", C.c_int32, C.c_void_p, C.c_uint64, C.c_uint32, C.c_uint32)
control = fn("xhci_control", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint64, C.c_void_p, C.c_uint32)
enumerate_ = fn("usb_enumerate", C.c_int32, C.c_void_p, C.c_uint32)
scan = fn("usb_scan", C.c_int32, C.c_void_p)
device_count = fn("usb_device_count", C.c_uint32)
device_get = fn("usb_device_get", C.c_void_p, C.c_uint32)
get_string = fn("usb_get_string", C.c_int32, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32)
get_descriptor = fn("usb_get_descriptor", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32, C.c_uint32,
                    C.c_void_p, C.c_uint32)
L = list((C.c_uint32 * 15).in_dll(lib, "xhci_layout"))
HC_SIZE, HC_MAX_SLOTS, HC_MAX_PORTS, HC_CTX, HC_SCRATCH, HC_DCBAA, HC_HANDOFF, HC_MAJOR, HC_SLOTS, \
    HC_CMD, HC_EVT_DEQ, HC_HC_EVENTS, HC_PORT_CHANGE, SLOT_EPS, EP_SIZE = L


class UsbDevice(C.Structure):
    _fields_ = [("hc", C.c_uint64), ("parent", C.c_uint64), ("slot", C.c_uint8), ("port", C.c_uint8),
                ("root_port", C.c_uint8), ("speed", C.c_uint8), ("route", C.c_uint32), ("depth", C.c_uint8),
                ("address", C.c_uint8), ("state", C.c_uint8), ("config_value", C.c_uint8),
                ("max_packet0", C.c_uint16), ("flags", C.c_uint16), ("desc", C.c_uint8 * 18),
                ("pad", C.c_uint8 * 6), ("config", C.c_uint64), ("config_raw", C.c_uint64),
                ("driver", C.c_uint64), ("driver_data", C.c_uint64)]


layout = list((C.c_uint32 * 7).in_dll(lib, "usb_layout"))
assert layout[5] == C.sizeof(UsbDevice), (layout[5], C.sizeof(UsbDevice))

# ---- memory and time for the driver --------------------------------------------------
ARENA = C.create_string_buffer(16 << 20)
arena = {"next": C.addressof(ARENA), "end": C.addressof(ARENA) + (16 << 20), "fail_after": None, "count": 0}


def alloc(size, align):
    if arena["fail_after"] is not None:
        if arena["count"] >= arena["fail_after"]:
            return 0
    arena["count"] += 1
    p = (arena["next"] + align - 1) & ~(align - 1)
    if p + size > arena["end"]:
        return 0
    arena["next"] = p + size
    return p


delays = [0]
sim = None
ALLOC = C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(alloc)
DELAY = C.CFUNCTYPE(None, C.c_uint64)(lambda us: delays.__setitem__(0, delays[0] + us))
RD = C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: sim.read(a) & 0xFFFFFFFF)
WR = C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: sim.write(a, v))
for name, cb in (("usb_alloc_fn", ALLOC), ("usb_delay_fn", DELAY), ("usb_rd32_fn", RD), ("usb_wr32_fn", WR)):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


def fresh(**kw):
    """A new controller; the driver's lists emptied as at boot."""
    global sim
    sim = X.XhciSim(**kw)
    C.c_uint32.in_dll(lib, "xhci_hc_count").value = 0
    C.c_uint32.in_dll(lib, "usb_device_total").value = 0
    delays[0] = 0
    return sim


def hc_u32(hc, off):
    return C.c_uint32.from_address(hc + off).value


def hc_u64(hc, off):
    return C.c_uint64.from_address(hc + off).value


def setup(rt, req, value, index, length):
    return struct.unpack("<Q", struct.pack("<BBHHH", rt, req, value, index, length))[0]


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# ---- bring-up ----------------------------------------------------------------------
fresh(scratchpads=3)
hc = attach(sim.base)
check("attached", bool(hc), True)
check("halted, reset, then run", ([e[0] for e in sim.log if e[0] == "hcrst"], sim.usbcmd & 1, sim.usbsts & 1),
      (["hcrst"], 1, 0))
check("firmware let go", (hc_u32(hc, HC_HANDOFF), sim.legsup & (1 << 16), bool(sim.legsup & (1 << 24))),
      (1, 0, True))
check("its SMIs off and latched events cleared", (sim.legctl & 0xE011, sim.legctl >> 29), (0, 0))
check("slots", (hc_u32(hc, HC_MAX_SLOTS), sim.config, hc_u32(hc, HC_MAX_PORTS), hc_u32(hc, HC_CTX)), (32, 32, 4, 32))
dcbaa = hc_u64(hc, HC_DCBAA)
check("device context array given", sim.dcbaa(), dcbaa)
sp = C.c_uint64.from_address(dcbaa).value
check("three scratchpad pages", (hc_u32(hc, HC_SCRATCH),
                                 [C.c_uint64.from_address(sp + 8 * k).value % 4096 == 0 and
                                  C.c_uint64.from_address(sp + 8 * k).value != 0 for k in range(3)]),
      (3, [True] * 3))
erst = [e for e in sim.log if e[0] == "erst"]
check("event ring: one segment, ERSTSZ before ERSTBA", (len(erst), erst[0][2], erst[0][3]), (1, 256, 1))
check("interrupter enabled", sim.iman & 2, 2)
check("ports: two USB 2, two USB 3", [C.c_uint8.from_address(hc + HC_MAJOR + p).value for p in range(1, 5)],
      [2, 2, 3, 3])

fresh(stubborn_bios=True)
hc = attach(sim.base)
check("firmware that will not let go is overruled", (bool(hc), hc_u32(hc, HC_HANDOFF), sim.legsup & (1 << 16)),
      (True, 2, 0))
fresh(bios_owned=False)
check("no firmware owner", hc_u32(attach(sim.base), HC_HANDOFF), 1)

fresh(reset_sticks=True)
r = attach(sim.base)
check("a reset that never ends", r, None)
fresh(csz=True)
hc = attach(sim.base)
check("64-byte contexts", hc_u32(hc, HC_CTX), 64)
fresh()
arena["fail_after"], arena["count"] = 3, 0
check("out of memory", attach(sim.base), None)
arena["fail_after"] = None

# ---- commands ----------------------------------------------------------------------
fresh()
hc = attach(sim.base)
codes = [command(hc, 0, 0, 23 << 10) for _ in range(150)]
check("150 no-op commands: the command ring wraps twice", (set(codes), sim.cmd_ccs), ({1}, 1))
check("an unknown slot", command(hc, 0, 0, (11 << 10) | (7 << 24)), 5)

# ---- enumeration ---------------------------------------------------------------------
fresh()
hc = attach(sim.base)
kbd, ms, bt, disk = D.keyboard(), D.mouse(), D.bluetooth(), D.superspeed_disk()
sim.attach(1, kbd)
sim.attach(2, bt)
sim.attach(3, disk)
n = scan(hc)
check("three devices", (n, device_count()), (3, 3))
devs = [UsbDevice.from_address(device_get(i)) for i in range(3)]
check("speeds, ports, slots", [(d.speed, d.root_port, d.slot, d.state) for d in devs],
      [(1, 1, 1, 2), (3, 2, 2, 2), (4, 3, 3, 2)])
check("addresses from the controller", [d.address for d in devs], [1, 2, 3])
check("vendor and product", [struct.unpack_from("<HH", bytes(d.desc), 8) for d in devs],
      [(0x046D, 0xC31C), (0x0E8D, 0x0608), (0x0781, 0x5583)])
check("EP0 packet sizes", [d.max_packet0 for d in devs], [8, 64, 512])
check("USB 2 ports reset, the USB 3 link trained by itself",
      [p.resets for p in sim.ports[:3]], [1, 1, 0])
addressed = [e for e in sim.log if e[0] == "address"]
check("Address Device: port, speed, EP0 size, route", [e[2:] for e in addressed],
      [(1, 1, 8, 0), (2, 3, 64, 0), (3, 4, 512, 0)])
check("full speed at 8 stays: no Evaluate Context", [e for e in sim.log if e[0] == "evaluate"], [])


def iface0(d):
    cfg = d.config
    return (C.c_uint8.from_address(cfg + 7).value,                 # iface_count
            C.c_uint8.from_address(cfg + 16 + 2).value)            # ifaces[0].class


check("configurations parsed", [iface0(d) for d in devs], [(1, 3), (3, 0xE0), (1, 8)])
check("not configured yet", [kbd.configuration, bt.configuration, disk.configuration], [0, 0, 0])
check("change bits acknowledged", [sim._portsc(k) & X.CHANGES for k in range(4)], [0, 0, 0, 0])

out = C.create_string_buffer(64)
check("strings", [(get_string(device_get(i), s, out, 64), out.value.decode()) for i, s in ((0, 1), (0, 2), (1, 1))],
      [(8, "Logitech"), (12, "USB Keyboard"), (13, "MediaTek Inc.")])
check("string 0 is not one", get_string(device_get(0), 0, out, 64), -1)
check("a string the device lacks: stalled", get_string(device_get(0), 9, out, 64), ESTALL)
check("and EP0 recovered: Reset Endpoint, Set TR Dequeue",
      [e[0] for e in sim.log if e[0] in ("reset_ep", "set_deq")][-2:], ["reset_ep", "set_deq"])
check("works again after", get_string(device_get(0), 1, out, 64), 8)

buf = C.create_string_buffer(255)
check("a short IN: bytes actually sent", get_descriptor(device_get(1), 1, 0, 0, buf, 255), 18)
check("BOS on the SuperSpeed disk", get_descriptor(device_get(2), 0x0F, 0, 0, buf, 255), len(disk.bos))
check("an OUT request with no data: SET_CONFIGURATION",
      (control(hc, 1, setup(0x00, 9, 1, 0, 0), None, 0), kbd.configuration), (0, 1))
check("GET_CONFIGURATION back", (control(hc, 1, setup(0x80, 8, 0, 0, 1), buf, 1), buf.raw[0]), (1, 1))

# a USB 3 link that did not train: warm reset
late = D.superspeed_disk()
late.untrained = True
sim.attach(4, late)
check("an untrained USB 3 link gets a warm reset", (enumerate_(hc, 4), sim.ports[3].warm_resets,
                                                    UsbDevice.from_address(device_get(3)).speed), (0, 1, 4))

# full speed at 64: corrected through Evaluate Context
fresh(usb2_ports=3, usb3_ports=1)
hc = attach(sim.base)
sim.attach(3, D.mouse(mps0=64))
check("a full-speed mouse at 64", (enumerate_(hc, 3), [e[2] for e in sim.log if e[0] == "evaluate"]), (0, [64]))
check("its device descriptor read whole after", UsbDevice.from_address(device_get(0)).desc[0], 18)

# ---- rings wrap ------------------------------------------------------------------------
before = sim.events_posted
codes = set()
for k in range(300):
    codes.add(control(hc, 1, setup(0x80, 6, 0x0100, 0, 18), buf, 18))
check("300 control transfers: EP0's ring and the event ring wrap", (codes, sim.events_posted - before > 256,
                                                                    sim.ring_full), ({18}, True, 0))

# ---- failures ------------------------------------------------------------------------
check("an empty port", port_reset(hc, 1), ENODEV)
check("enumerating it", enumerate_(hc, 1), ENODEV)
sim.detach(3)
check("a device that went away", control(hc, 1, setup(0x80, 6, 0x0100, 0, 18), buf, 18), -6)
sim.attach(2, D.keyboard())
check("a new device after", enumerate_(hc, 2), 0)
sim.deaf = True
delays[0] = 0
r = control(hc, 2, setup(0x80, 6, 0x0100, 0, 18), buf, 18)
check("a device that never answers: timeout after a second", (r, 990_000 <= delays[0] <= 1_010_000), (ETIMEOUT, True))
sim.deaf = False
fresh(max_slots=2)
hc = attach(sim.base)
for p, d in ((1, D.keyboard()), (2, D.mouse()), (4, D.superspeed_disk())):
    sim.attach(p, d)
lib.xhci_poll(C.c_void_p(hc))
check("port status change events seen", C.c_uint8.from_address(hc + HC_PORT_CHANGE).value, 0b10110)
check("more devices than slots", (scan(hc), C.c_uint32.in_dll(lib, "usb_enum_errors").value > 0), (2, True))

print(f"test_xhci: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

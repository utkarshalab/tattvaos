"""HCI over USB (tr/usb.asm) and the HCI core (hci/core.asm) against a
simulated USB Bluetooth controller on the simulated xHCI controller.

usage: python3 test_usb_hci.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "usb", "sim"))
import hci_usb as B  # noqa: E402
import devices as D  # noqa: E402
import xhci_sim as X  # noqa: E402

lib = C.CDLL(sys.argv[1])
UP, NEED_FIRMWARE, FAILED, GONE = 1, 2, 3, 4
ETIMEOUT, EBUSY, EDOWN = -1, -3, -4


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
poll = fn("xhci_poll", C.c_int32, C.c_void_p)
ubt_init = fn("ubt_init", None)
adapter_get = fn("ubt_adapter_get", C.c_void_p, C.c_uint32)
adapter_count = fn("ubt_adapter_count", C.c_uint32)
hci_cmd = fn("ubt_hci_cmd", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
acl_send = fn("ubt_acl_send", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
service = fn("ubt_service", None)
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731
L = list((C.c_uint32 * 30).in_dll(lib, "ubt_layout"))
(O_STATE, O_INDEX, O_CREDITS, O_FAILED_OP, O_FAILED_STATUS, O_HCI_VER, O_HCI_REV, O_LMP_VER, O_MANUF, O_LMP_SUB,
 O_BDADDR, O_LE, O_FEATURES, O_COMMANDS, O_ACL_MTU, O_SCO_MTU, O_ACL_COUNT, O_SCO_COUNT, O_LE_MTU, O_LE_COUNT,
 O_EVENTS, O_ACL_RX, O_ACL_TX, O_ERRORS, O_HW_ERRORS, O_EVENT_FN, O_ACL_FN, O_WAIT_BUF, O_OUT_BUSY, ADAPTER_SIZE) = L

ARENA = C.create_string_buffer(32 << 20)
arena = {"next": C.addressof(ARENA)}
live = {}


def alloc(size, align):
    p = (arena["next"] + align - 1) & ~(align - 1)
    arena["next"] = p + size
    live[p] = size
    return p


def free(p, size, align):
    assert live.pop(p) == size


sim = None
delays = [0]


def delay(us):
    delays[0] += us
    sim.pump()                      # time passes: the device sends what it has


told = []
hooks = [C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(alloc),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint64, C.c_uint64)(free),
         C.CFUNCTYPE(None, C.c_uint64)(delay),
         C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: sim.read(a) & 0xFFFFFFFF),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: sim.write(a, v)),
         C.CFUNCTYPE(None, C.c_uint64)(lambda a: told.append(C.c_uint32.from_address(a + O_STATE).value))]
for name, cb in zip(("usb_alloc_fn", "usb_free_fn", "usb_delay_fn", "usb_rd32_fn", "usb_wr32_fn",
                     "ubt_adapter_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value

events, acls = [], []
EVENT_FN = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(
    lambda a, p, n: events.append(C.string_at(p, n)))
ACL_FN = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(lambda a, p, n: acls.append(C.string_at(p, n)))


def fresh(*ctrls):
    global sim
    sim = X.XhciSim(usb2_ports=4, usb3_ports=0)
    for n in ("xhci_hc_count", "usb_device_total", "usb_hid_count", "usb_hub_count", "usb_driver_count"):
        u32(n).value = 0
    ubt_init()
    told.clear()
    hc = attach(sim.base)
    for i, c in enumerate(ctrls):
        sim.attach(i + 1, c)
    scan(hc)
    taken = [attach_drivers(device_get(i)) for i in range(len(ctrls))]
    return hc, taken


def a8(a, off):
    return C.c_uint8.from_address(a + off).value


def a16(a, off):
    return C.c_uint16.from_address(a + off).value


def a32(a, off):
    return C.c_uint32.from_address(a + off).value


def settle(hc):
    for _ in range(3):
        sim.pump()
        poll(hc)


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


# ---- bring-up -------------------------------------------------------------------------
ctrl = B.HciController()
hc, taken = fresh(ctrl)
a = adapter_get(0)
check("taken by the Bluetooth driver, not as input", (taken, adapter_count(), u32("usb_hid_count").value), ([1], 1, 0))
check("the bring-up, in order", ctrl.commands,
      [0x0C03, 0x1001, 0x1002, 0x1003, 0x1005, 0x1009, 0x0C01, 0x2002, 0x2001])
check("up, hci0, told", (a32(a, O_STATE), a32(a, O_INDEX), told), (UP, 0, [UP]))
check("version and maker", (a8(a, O_HCI_VER), a16(a, O_HCI_REV), a8(a, O_LMP_VER), a16(a, O_MANUF), a16(a, O_LMP_SUB)),
      (0x0B, 0x1234, 0x0B, 0x0059, 0x5678))
check("address, LE, features, commands",
      (C.string_at(a + O_BDADDR, 6), a8(a, O_LE), a8(a, O_FEATURES), C.string_at(a + O_COMMANDS, 64)),
      (bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66]), 1, 0xFF, bytes(range(64))))
check("buffer sizes, BR/EDR and LE", (a16(a, O_ACL_MTU), a8(a, O_SCO_MTU), a16(a, O_ACL_COUNT), a16(a, O_SCO_COUNT),
                                     a16(a, O_LE_MTU), a8(a, O_LE_COUNT)), (1021, 64, 8, 16, 251, 15))
check("the event masks sent", (ctrl.params[0x0C01], ctrl.params[0x2001]),
      (bytes([0xFF, 0xFF, 0xFB, 0xFF, 0x07, 0xF8, 0xBF, 0x3D]), bytes([0xFF, 0xFF, 0x0F, 0, 0, 0, 0, 0])))
check("commands go to interface 0 as class requests", {r[:4] for r in ctrl.requests if r[0] == 0x20}, {(0x20, 0, 0, 0)})
check("events came in 16-byte pieces and were put together", (a32(a, O_EVENTS) >= 9, a32(a, O_ERRORS)), (True, 0))
check("credits from the last Command Complete", a32(a, O_CREDITS), 1)
check("endpoints configured: events, ACL in and out", sorted(sim.slots[1].eps), [1, 3, 4, 5])

# ---- commands after bring-up -----------------------------------------------------------
check("a command the controller does not know: its status", hci_cmd(a, 0xFC00, b"", 0), 0x01)
ctrl.with_status.add(0x0405)
check("one answered with Command Status", hci_cmd(a, 0x0405, b"\x00" * 13, 13), 0)
ctrl.ignore.add(0x1004)
delays[0] = 0
check("one never answered: a timeout after a second", (hci_cmd(a, 0x1004, b"\x01", 1), delays[0] >= 990000),
      (ETIMEOUT, True))

# ---- other events to the layers above ---------------------------------------------------
C.c_void_p.from_address(a + O_EVENT_FN).value = C.cast(EVENT_FN, C.c_void_p).value
ctrl.event(0x05, bytes([0, 0x40, 0x00, 0x13]))                 # Disconnection Complete
ctrl.event(0x3E, bytes([0x02]) + bytes(40))                    # an LE meta event, 3 pieces
ctrl.event(B.EV_HW_ERROR, b"\x01")
settle(hc)
check("other events handed up whole", [(e[0], len(e)) for e in events], [(0x05, 6), (0x3E, 43), (0x10, 3)])
check("a hardware error counted", a32(a, O_HW_ERRORS), 1)
ctrl.event(0x0E, bytes([1, 0x34, 0x12, 0]))                     # Command Complete nobody waits for
settle(hc)
check("an unexpected Command Complete goes up too", events[-1][:5], bytes([0x0E, 4, 1, 0x34, 0x12]))
events.clear()
ctrl.ev_mps = 16
ctrl.event(0x08, bytes(14))                                     # exactly 16 bytes: a zero-length packet after
settle(hc)
check("an event of exactly one packet, then a zero-length one", [len(e) for e in events], [16])

# ---- ACL ----------------------------------------------------------------------------------
C.c_void_p.from_address(a + O_ACL_FN).value = C.cast(ACL_FN, C.c_void_p).value
pkt = struct.pack("<HH", 0x0040 | 0x2000, 300) + bytes(i & 0xFF for i in range(300))
ctrl.echo, ctrl.echo_pieces = True, 3
check("an ACL packet out", acl_send(a, pkt, len(pkt)), 0)
check("one at a time", acl_send(a, pkt, len(pkt)), EBUSY)
settle(hc)
check("it went out whole", ctrl.acl_out[-1], (0x02, pkt))
check("and came back in three pieces, put together", acls, [pkt])
check("counted", (a32(a, O_ACL_TX), a32(a, O_ACL_RX), a32(a, O_OUT_BUSY)), (1, 1, 0))
acls.clear()
small = [struct.pack("<HH", 0x0041, 4) + bytes([n] * 4) for n in range(3)]
ctrl.echo = False
ctrl.queue(0x82, b"".join(small))                               # three in one transfer
settle(hc)
check("three packets in one transfer: three packets", acls, small)
acls.clear()
ctrl.queue(0x82, struct.pack("<HH", 0x0041, 2000))              # longer than any packet
ctrl.queue(0x82, small[0])
settle(hc)
check("a length no packet has: dropped, then back in step", (acls, a32(a, O_ERRORS) >= 1), ([small[0]], True))

# ---- endpoints failing --------------------------------------------------------------------
ctrl.queue(0x81, "stall")
settle(hc)
service()
ctrl.event(0x05, bytes(4))
settle(hc)
check("the event endpoint stalled, recovered by the service", events[-1][:1], b"\x05")

# ---- a controller that fails bring-up ------------------------------------------------------
bad = B.HciController()
bad.refuse[0x1005] = 0x0C                                        # Command Disallowed
hc, taken = fresh(bad)
a = adapter_get(0)
check("failed at Read Buffer Size, with its status", (a32(a, O_STATE), a32(a, O_FAILED_OP), a32(a, O_FAILED_STATUS),
                                                      told), (FAILED, 0x1005, 0x0C, [FAILED]))
check("nothing sent once down", acl_send(a, pkt, len(pkt)), EDOWN)
mute = B.HciController()
mute.ignore.add(0x0C03)
hc, taken = fresh(mute)
a = adapter_get(0)
check("a controller that never answers its reset", (a32(a, O_STATE), a32(a, O_FAILED_OP), a32(a, O_FAILED_STATUS)),
      (FAILED, 0x0C03, 0xFFFFFFFF))

# ---- BR/EDR only; two adapters --------------------------------------------------------------
c1, c2 = B.HciController(le=False), B.HciController(address=bytes(6))
hc, taken = fresh(c1, c2)
check("two adapters: hci0 and hci1", [a32(adapter_get(i), O_INDEX) for i in range(2)], [0, 1])
check("no LE: no LE commands", (a8(adapter_get(0), O_LE), [op for op in c1.commands if op >> 10 == 8]), (0, []))

# ---- MediaTek: firmware first ------------------------------------------------------------------
mtk = B.HciController(vid=0x0E8D, pid=0x0608)
hc, taken = fresh(mtk)
a = adapter_get(0)
check("the laptop's MediaTek radio: claimed, nothing sent, firmware needed",
      (taken, a32(a, O_STATE), mtk.commands, told), ([1], NEED_FIRMWARE, [], [NEED_FIRMWARE]))

# ---- pulled out ------------------------------------------------------------------------------------
ctrl = B.HciController()
hc, taken = fresh(ctrl)
before = dict(live)
mine = adapter_get(0)
told.clear()
remove(C.c_void_p(device_get(0)))
check("unplugged: gone from the list, told, its memory back",
      (adapter_count(), told, len(live) < len(before)), (0, [GONE], True))
check("its adapter record given back", mine in live, False)

print(f"test_usb_hci: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

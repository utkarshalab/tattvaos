"""ACL links (hci/conn.asm) and L2CAP (l2cap/core.asm, l2cap/sig.asm): two
of our stacks, on the in-memory transport, talking through the virtual
radio in sim/radio.py; and frames built by hand where the bytes matter.

usage: python3 test_l2cap.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import radio as R  # noqa: E402

lib = C.CDLL(sys.argv[1])
UP, DOWN, FAILED = 1, 2, 3
EV_OPEN, EV_CLOSED, EV_REFUSED = 1, 2, 3
WHY_TIMEOUT, WHY_LINK, WHY_PEER = 0x1000, 0x1001, 0x1002


class Conn(C.Structure):
    _fields_ = [("adapter", C.c_uint64), ("handle", C.c_uint16), ("type", C.c_uint8), ("role", C.c_uint8),
                ("peer", C.c_uint8 * 6), ("peer_type", C.c_uint8), ("state", C.c_uint8), ("pad0", C.c_uint32),
                ("tx_head", C.c_uint64), ("tx_tail", C.c_uint64), ("in_flight", C.c_uint32),
                ("rx_len", C.c_uint32), ("rx_need", C.c_uint32), ("ident", C.c_uint8), ("info_state", C.c_uint8),
                ("info_ident", C.c_uint8), ("pad", C.c_uint8), ("ext_features", C.c_uint32), ("pad2", C.c_uint32),
                ("fixed_chans", C.c_uint64), ("rx_buf", C.c_uint64), ("user", C.c_uint64),
                ("att", C.c_uint64), ("smp", C.c_uint64), ("pair", C.c_uint64), ("rfcomm", C.c_uint64),
                ("sec", C.c_uint8), ("key_size", C.c_uint8), ("pad3", C.c_uint8 * 6)]


class Chan(C.Structure):
    _fields_ = [("conn", C.c_uint64), ("ops", C.c_uint64), ("user", C.c_uint64), ("deadline", C.c_uint64),
                ("scid", C.c_uint16), ("dcid", C.c_uint16), ("psm", C.c_uint16), ("imtu", C.c_uint16),
                ("omtu", C.c_uint16), ("state", C.c_uint8), ("mode", C.c_uint8), ("ident", C.c_uint8),
                ("cfg", C.c_uint8), ("outgoing", C.c_uint8), ("pad", C.c_uint8),
                ("peer_txwin", C.c_uint8), ("peer_maxtx", C.c_uint8), ("peer_mps", C.c_uint16),
                ("retrans_ms", C.c_uint16), ("monitor_ms", C.c_uint16), ("cred", C.c_uint64), ("ertm", C.c_uint64)]


class Ops(C.Structure):
    _fields_ = [("recv", C.c_void_p), ("event", C.c_void_p)]


layout = list((C.c_uint32 * 8).in_dll(lib, "l2cap_layout"))
assert layout == [C.sizeof(Conn), Conn.tx_head.offset, Conn.ext_features.offset, Conn.rx_buf.offset,
                  C.sizeof(Chan), Chan.scid.offset, Chan.state.offset, C.sizeof(Ops)], layout

# ---- memory, time ------------------------------------------------------------------------------
ARENA = C.create_string_buffer(32 << 20)
arena = {"next": C.addressof(ARENA)}
live = {}


def alloc(size, align):
    p = (arena["next"] + align - 1) & ~(align - 1)
    arena["next"] = p + size
    live[p] = size
    return p


def free(p, size, align):
    assert live.pop(p) == size, "freed with another size"


now = [1000]
hooks = [C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(alloc),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint64, C.c_uint64)(free),
         C.CFUNCTYPE(None, C.c_uint64)(lambda us: None),
         C.CFUNCTYPE(C.c_uint64)(lambda: now[0])]
for name, cb in zip(("usb_alloc_fn", "usb_free_fn", "usb_delay_fn", "ubt_clock_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


connect = fn("ubt_connect", C.c_int32, C.c_void_p, C.c_char_p)
le_connect = fn("ubt_le_connect", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
disconnect = fn("ubt_disconnect", None, C.c_void_p, C.c_uint32)
server = fn("l2cap_server", C.c_int32, C.c_uint32, C.c_uint32, C.c_void_p, C.c_void_p)
l2connect = fn("l2cap_connect", C.c_void_p, C.c_void_p, C.c_uint32, C.c_uint32, C.c_void_p, C.c_void_p)
l2send = fn("l2cap_send", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
l2disconnect = fn("l2cap_disconnect", None, C.c_void_p)
echo = fn("l2cap_echo", None, C.c_void_p, C.c_char_p, C.c_uint32)
service = fn("ubt_service", None)
remove = fn("ubt_mem_remove", None, C.c_void_p)


# ---- what the users see ------------------------------------------------------------------------
class Side:
    def __init__(self, name):
        self.name = name
        self.links = []             # (event, conn)
        self.events = []            # (chan, event, why)
        self.data = []              # (chan, bytes)
        self.echoes = []
        self.conn_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(
            lambda a, ev, c: self.links.append((ev, c)))
        self.recv_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(
            lambda ch, p, n: self.data.append((ch, C.string_at(p, n))))
        self.event_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_uint32)(
            lambda ch, ev, why: self.events.append((ch, ev, why)))
        self.ops = Ops(C.cast(self.recv_cb, C.c_void_p).value, C.cast(self.event_cb, C.c_void_p).value)

    def conn(self):
        ups = [c for ev, c in self.links if ev == UP]
        return ups[-1] if ups else None


A_ADDR, B_ADDR = bytes([0xAA] * 6), bytes([0xBB, 1, 2, 3, 4, 5])
radio = R.Radio(lib)
a, ca = radio.add(A_ADDR)
b, cb = radio.add(B_ADDR)
SA, SB = Side("A"), Side("B")


def set_hooks(adapter, side):
    # conn_fn sits right after acl_fn, whose offset ubt_layout gives
    L = list((C.c_uint32 * 30).in_dll(lib, "ubt_layout"))
    acl_fn = L[26]
    C.c_void_p.from_address(adapter + acl_fn + 8).value = C.cast(side.conn_cb, C.c_void_p).value


set_hooks(a, SA)
set_hooks(b, SB)
echo_got = []
ECHO = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(lambda c, p, n: echo_got.append(C.string_at(p, n)))
C.c_void_p.in_dll(lib, "l2cap_echo_fn").value = C.cast(ECHO, C.c_void_p).value


def settle(rounds=8):
    for _ in range(rounds):
        radio.run()
        service()
    radio.run()


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def frames(ctrl, start=0):
    """The L2CAP frames a controller's host sent (fragments put together)."""
    out, cur = [], b""
    for h, pb, data in ctrl.sent[start:]:
        if pb in (0, 2):
            cur = data
        else:
            cur += data
        if len(cur) >= 4 and len(cur) == struct.unpack_from("<H", cur)[0] + 4:
            out.append(cur)
            cur = b""
    return out


def sig_frames(ctrl, start=0, cid=1):
    """Signalling commands (code, ident, data) a host sent."""
    out = []
    for f in frames(ctrl, start):
        if struct.unpack_from("<H", f, 2)[0] != cid:
            continue
        p = f[4:]
        while len(p) >= 4:
            code, ident, n = struct.unpack_from("<BBH", p)
            out.append((code, ident, p[4:4 + n]))
            p = p[4 + n:]
    return out


# ---- a BR/EDR link ---------------------------------------------------------------------------
check("both adapters up through the in-memory transport", (len(ca.commands), len(cb.commands)), (9, 9))
connect(a, B_ADDR)
settle()
ka, kb = SA.conn(), SB.conn()
check("A pages B, B accepts: a link on both sides", (bool(ka), bool(kb), 0x0405 in ca.commands, 0x0409 in cb.commands),
      (True, True, True, True))
A_conn, B_conn = Conn.from_address(ka), Conn.from_address(kb)
check("roles: A central, B peripheral; each knows the other",
      (A_conn.role, B_conn.role, bytes(A_conn.peer), bytes(B_conn.peer), A_conn.type), (0, 1, B_ADDR, A_ADDR, 0))
check("each asked what the other's L2CAP does, and was told",
      (A_conn.info_state, B_conn.info_state, A_conn.ext_features, A_conn.fixed_chans), (2, 2, 0x4B8, 0x02))
info = [s for s in sig_frames(ca) if s[0] == 0x0A]
check("Information Requests: extended features, then fixed channels",
      [(c, d) for c, i, d in info], [(0x0A, b"\x02\x00"), (0x0A, b"\x03\x00")])

# ---- a channel ---------------------------------------------------------------------------------
check("a server on B", (server(0x1001, 0, C.byref(SB.ops), None), server(0x1001, 0, C.byref(SB.ops), None)), (0, -3))
mark = len(ca.sent)
ch_a = l2connect(ka, 0x1001, 0, C.byref(SA.ops), None)
settle()
check("open on both sides", ([e[1:] for e in SA.events], [e[1:] for e in SB.events]), ([(EV_OPEN, 0)], [(EV_OPEN, 0)]))
ch_b = SB.events[0][0]
A_ch, B_ch = Chan.from_address(ch_a), Chan.from_address(ch_b)
check("CIDs and MTUs: each knows the other's", (A_ch.scid, A_ch.dcid, B_ch.scid, B_ch.dcid, A_ch.omtu, B_ch.omtu),
      (0x40, B_ch.scid, B_ch.scid, 0x40, 1017, 1017))
req = frames(ca, mark)[0]
check("the Connection Request on the air, byte for byte",
      req, struct.pack("<HHBBHHH", 8, 1, 0x02, req[5], 4, 0x1001, 0x0040))
confs = [s for s in sig_frames(ca, mark) if s[0] == 0x04]
check("A's Configuration Request: B's CID, complete, MTU 1017", confs[0][2], struct.pack("<HHBBH", B_ch.scid, 0, 1, 2, 1017))

# ---- data ------------------------------------------------------------------------------------------
sdu = bytes(i & 0xFF for i in range(900))
before = len(ca.sent)
check("A sends 900 bytes", l2send(ch_a, sdu, len(sdu)), 0)
settle()
check("B gets them whole", SB.data, [(ch_b, sdu)])
check("cut into the controller's 27-byte buffers, three at a time",
      (len(ca.sent) - before, {len(d) for h, pb, d in ca.sent[before:-1]}, A_conn.in_flight), (34, {27}, 0))
SB.data.clear()
l2send(ch_b, b"hello", 5)
settle()
check("and back", SA.data, [(ch_a, b"hello")])
check("too long for the peer", l2send(ch_a, bytes(1018), 1018), -2)
ca.hold_completed = True
l2send(ch_a, bytes(300), 300)
settle()
check("the controller's buffers full: the rest waits", (A_conn.in_flight, A_conn.tx_head != 0), (3, True))
ca.release()
settle()
check("buffers back: it goes", (A_conn.in_flight, A_conn.tx_head, len(SB.data)), (0, 0, 1))

# ---- echo, refusals ------------------------------------------------------------------------------
echo(ka, b"ping", 4)
settle()
check("echo", echo_got, [b"ping"])
SA.events.clear()
ch_x = l2connect(ka, 0x1003, 0, C.byref(SA.ops), None)
settle()
check("a PSM nobody serves: refused", [e for e in SA.events if e[0] == ch_x], [(ch_x, EV_REFUSED, 2)])

# ---- closing ---------------------------------------------------------------------------------------
SA.events.clear()
SB.events.clear()
l2disconnect(ch_a)
settle()
check("A closes: closed on both sides", ([e[1:] for e in SA.events], [e[1:] for e in SB.events]),
      ([(EV_CLOSED, 0)], [(EV_CLOSED, WHY_PEER)]))
ch_a = l2connect(ka, 0x1001, 0, C.byref(SA.ops), None)
settle()
ch_b = [e[0] for e in SB.events if e[1] == EV_OPEN][-1]
SA.events.clear()
SB.events.clear()
disconnect(ka, 0x13)
settle()
check("the link goes: every channel on it closed", ([e[1:] for e in SA.events], [e[1:] for e in SB.events]),
      ([(EV_CLOSED, WHY_LINK)], [(EV_CLOSED, WHY_LINK)]))
check("and the link said gone on both sides", ([ev for ev, c in SA.links][-1], [ev for ev, c in SB.links][-1]),
      (DOWN, DOWN))

# ---- the peer goes quiet ------------------------------------------------------------------------------
connect(a, B_ADDR)
settle()
ka, kb = SA.conn(), SB.conn()
cb.deaf = True
SA.events.clear()
ch_q = l2connect(ka, 0x1001, 0, C.byref(SA.ops), None)
settle()
now[0] += 9000
settle()
check("no answer yet", SA.events, [])
now[0] += 2000
settle()
check("no answer in time: closed", [e[1:] for e in SA.events], [(EV_CLOSED, WHY_TIMEOUT)])
cb.deaf = False


# ---- signalling by hand: what B answers --------------------------------------------------------
def to_b(code, ident, data, cid=1):
    cmd = struct.pack("<BBH", code, ident, len(data)) + bytes(data)
    frame = struct.pack("<HH", len(cmd), cid) + cmd
    radio.inject(cb, B_conn_handle(), 2, frame)
    mark = len(cb.sent)
    settle()
    return sig_frames(cb, mark, cid)


def B_conn_handle():
    return Conn.from_address(SB.conn()).handle


ca.deaf = True                  # A says nothing back: only B's answers here
check("an unknown command: Command Reject, not understood", to_b(0x50, 7, b"xy"), [(0x01, 7, b"\x00\x00")])
check("identifier 0: ignored", to_b(0x08, 0, b"x"), [])
check("Echo Request answered with its data", to_b(0x08, 9, b"abc"), [(0x09, 9, b"abc")])
check("Information: features, fixed channels, connectionless MTU, an unknown type",
      [to_b(0x0A, 10 + t, struct.pack("<H", t))[0][2] for t in (2, 3, 1, 9)],
      [struct.pack("<HHI", 2, 0, 0x4B8), struct.pack("<HHQ", 3, 0, 2), struct.pack("<HHH", 1, 0, 672),
       struct.pack("<HH", 9, 1)])
check("a Connection Request for a PSM nobody serves", to_b(0x02, 20, struct.pack("<HH", 0x0F01, 0x0050)),
      [(0x03, 20, struct.pack("<HHHH", 0, 0x0050, 2, 0))])
check("... with a fixed CID as its own", to_b(0x02, 21, struct.pack("<HH", 0x1001, 0x0005)),
      [(0x03, 21, struct.pack("<HHHH", 0, 0x0005, 6, 0))])
got = to_b(0x02, 22, struct.pack("<HH", 0x1001, 0x0060))
new_cid = struct.unpack_from("<H", got[0][2])[0]
check("a good one: success, and B's own Configuration Request after",
      ([g[0] for g in got], got[0][2][2:], struct.unpack_from("<H", got[1][2])[0]),
      ([0x03, 0x04], struct.pack("<HHH", 0x0060, 0, 0), 0x0060))
check("... with it in use already", to_b(0x02, 23, struct.pack("<HH", 0x1001, 0x0060))[0][2][4:6], b"\x07\x00")


def conf(ident, options, flags=0):
    return to_b(0x04, ident, struct.pack("<HH", new_cid, flags) + options)


check("Configuration Request, MTU 600: accepted", conf(30, struct.pack("<BBH", 1, 2, 600)),
      [(0x05, 30, struct.pack("<HHH", 0x0060, 0, 0))])
check("MTU 40: unacceptable, with the least we take",
      conf(31, struct.pack("<BBH", 1, 2, 40)), [(0x05, 31, struct.pack("<HHHBBH", 0x0060, 0, 1, 1, 2, 48))])
check("an unknown option: named back", conf(32, struct.pack("<BBH", 0x33, 2, 0)),
      [(0x05, 32, struct.pack("<HHHB", 0x0060, 0, 3, 0x33))])
check("an unknown hint: ignored", conf(33, struct.pack("<BBH", 0xB3, 2, 0)), [(0x05, 33, struct.pack("<HHH", 0x0060, 0, 0))])
check("another mode asked for: unacceptable, with basic", conf(34, struct.pack("<BB9s", 4, 9, b"\x03" + bytes(8)))[0][2][4:9],
      struct.pack("<HBBB", 1, 4, 9, 0))
check("an option running past the end: rejected", conf(35, b"\x01\x05\x00"), [(0x05, 35, struct.pack("<HHH", 0x0060, 0, 2))])
check("continuation: success, flag echoed", conf(36, struct.pack("<BBH", 1, 2, 600), flags=1),
      [(0x05, 36, struct.pack("<HHH", 0x0060, 1, 0))])
check("a request for a CID B does not have: Command Reject, invalid CID",
      to_b(0x04, 37, struct.pack("<HH", 0x0099, 0)), [(0x01, 37, struct.pack("<HHH", 2, 0x0099, 0))])
check("a Disconnection Request with the wrong CIDs: invalid CID",
      to_b(0x06, 38, struct.pack("<HH", new_cid, 0x0061))[0][:2], (0x01, 38))
check("the right ones: answered", to_b(0x06, 39, struct.pack("<HH", new_cid, 0x0060)),
      [(0x07, 39, struct.pack("<HH", new_cid, 0x0060))])

ca.deaf = False

# ---- LE ---------------------------------------------------------------------------------------------
SA.links.clear()
SB.links.clear()
le_connect(a, B_ADDR, 0)
settle()
la, lb = SA.conn(), SB.conn()
LA, LB = Conn.from_address(la), Conn.from_address(lb)
check("an LE link: A central, B peripheral, nothing to ask", (LA.type, LA.role, LB.role, LA.info_state), (1, 0, 1, 2))


def to_a_le(code, ident, data):
    cmd = struct.pack("<BBH", code, ident, len(data)) + bytes(data)
    radio.inject(ca, LA.handle, 0, struct.pack("<HH", len(cmd), 5) + cmd)
    mark = len(ca.sent)
    settle()
    return sig_frames(ca, mark, 5)


check("Connection Parameter Update from the peripheral: accepted, applied",
      (to_a_le(0x12, 50, struct.pack("<HHHH", 24, 40, 0, 500)), ca.updates[-1:]),
      ([(0x13, 50, b"\x00\x00")], [struct.pack("<HHHHHHH", LA.handle, 24, 40, 0, 500, 0, 0)]))
check("nonsense values: rejected", to_a_le(0x12, 51, struct.pack("<HHHH", 40, 24, 0, 500)), [(0x13, 51, b"\x01\x00")])
check("a timeout too short for the interval: rejected", to_a_le(0x12, 52, struct.pack("<HHHH", 3200, 3200, 0, 10)),
      [(0x13, 52, b"\x01\x00")])
check("an LE command not known: Command Reject", to_a_le(0x55, 53, b""), [(0x01, 53, b"\x00\x00")])
cmd = struct.pack("<BBH", 0x12, 54, 8) + struct.pack("<HHHH", 24, 40, 0, 500)
radio.inject(cb, LB.handle, 0, struct.pack("<HH", len(cmd), 5) + cmd)
mark = len(cb.sent)
settle()
check("the peripheral is asked: Command Reject", sig_frames(cb, mark, 5), [(0x01, 54, b"\x00\x00")])
mark = len(ca.sent)
radio.inject(ca, LA.handle, 0, struct.pack("<HH", 4, 1) + b"\x08\x01\x00\x00")    # BR/EDR echo, on LE
settle()
check("BR/EDR signalling on an LE link: dropped, no answer", sig_frames(ca, mark, 1), [])

# ---- fixed channels, odd data --------------------------------------------------------------------------
fixed = []
FIXED = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32)(
    lambda c, cid, p, n: fixed.append((cid, C.string_at(p, n))))
L = list((C.c_uint32 * 30).in_dll(lib, "ubt_layout"))
C.c_void_p.from_address(a + L[26] + 16).value = C.cast(FIXED, C.c_void_p).value      # fixed_fn
mark = len(ca.sent)
radio.inject(ca, LA.handle, 0, struct.pack("<HH", 3, 4) + b"\x02\x17\x00")             # ATT
radio.inject(ca, LA.handle, 0, struct.pack("<HH", 2, 6) + b"\x01\x02")                 # SMP
settle()
check("ATT to the GATT server (an MTU request answered), nothing to the fixed channel hook",
      ([f[4:] for f in frames(ca, mark) if struct.unpack_from("<H", f, 2)[0] == 4], fixed), ([b"\x03\x05\x02"], []))
radio.inject(ca, LA.handle, 0, struct.pack("<HH", 2, 0x0003) + b"\x01\x02")             # another fixed CID
settle()
check("other fixed channels to the hook", fixed, [(3, b"\x01\x02")])
check("SMP to the Security Manager: a broken Pairing Request answered Pairing Failed",
      [f[4:] for f in frames(ca, mark) if struct.unpack_from("<H", f, 2)[0] == 6], [b"\x05\x0a"])
dropped = C.c_uint32.in_dll(lib, "l2cap_dropped").value
radio.inject(ca, LA.handle, 0, struct.pack("<HH", 9, 4) + b"\x02")                      # says 9, has 1
settle()
radio.inject(ca, LA.handle, 0, struct.pack("<HH", 4, 0x0077) + b"abcd")                 # no such channel
settle()
check("frames that do not add up, or for no channel: dropped", C.c_uint32.in_dll(lib, "l2cap_dropped").value - dropped,
      1)
cut = C.c_uint32.in_dll(lib, "ubt_conn_dropped").value
radio.inject(ca, LA.handle, 1, b"stray")                                                # a continuation of nothing
settle()
check("a continuation with nothing started: dropped", C.c_uint32.in_dll(lib, "ubt_conn_dropped").value - cut, 1)

# ---- everything given back ----------------------------------------------------------------------------
disconnect(la, 0x13)
settle()
remove(a)
remove(b)
check("both adapters removed: every block given back", sorted(live.values()), [])

print(f"test_l2cap: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

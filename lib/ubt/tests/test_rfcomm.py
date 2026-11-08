"""RFCOMM (rfcomm/rfcomm.asm): two of our stacks over a BR/EDR link on the
virtual radio; frames checked here (FCS, addresses, lengths), credits,
the multiplexer's commands, refusals, frames made by hand.

usage: python3 test_rfcomm.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env, Ops  # noqa: E402

E = Env(sys.argv[1])
check, lib = E.check, E.lib
fn = E.fn
OPEN, CLOSED, REFUSED = 1, 2, 3
init = fn("ubt_rfcomm_init", None)
server = fn("ubt_rfcomm_server", C.c_int32, C.c_uint32, C.c_void_p, C.c_void_p)
connect = fn("ubt_rfcomm_connect", C.c_void_p, C.c_void_p, C.c_uint32, C.c_void_p, C.c_void_p)
send = fn("ubt_rfcomm_send", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
close = fn("ubt_rfcomm_close", None, C.c_void_p)
L = list((C.c_uint32 * 8).in_dll(lib, "ubt_rfc_layout"))


def crc8(data):
    crc = 0xFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xE0 if crc & 1 else crc >> 1
    return 0xFF - crc


check("the FCS of 'SABM on DLCI 0' (address, control, length) as TS 07.10 gives it",
      crc8(bytes([0x03, 0x3F, 0x01])), 0x1C)


class Side:
    def __init__(self):
        self.events, self.data = [], []
        self.rcb = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(
            lambda d, p, n: self.data.append((d, C.string_at(p, n))))
        self.ecb = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_uint32)(
            lambda d, ev, why: self.events.append((d, ev)))
        self.ops = Ops(C.cast(self.rcb, C.c_void_p).value, C.cast(self.ecb, C.c_void_p).value)


SA, SB = Side(), Side()
init()
check("B serves channel 3", server(3, C.byref(SB.ops), None), 0)
check("not twice", server(3, C.byref(SB.ops), None), -3)
ka, kb = E.link()


def rfc_frames(ctrl, start):
    """RFCOMM frames a side sent (on L2CAP channels, not signalling)."""
    out = []
    for f in E.frames(ctrl, start):
        if struct.unpack_from("<H", f, 2)[0] >= 0x40:
            out.append(f[4:])
    return out


def info(frame):
    """(DLCI, C/R, control, payload, FCS good)."""
    addr, ctl = frame[0], frame[1]
    if frame[2] & 1:
        n, hl = frame[2] >> 1, 3
    else:
        n, hl = (frame[2] >> 1) | (frame[3] << 7), 4
    body = frame[hl:-1]
    covered = frame[:2] if (ctl & ~0x10) == 0xEF else frame[:hl]
    return addr >> 2, (addr >> 1) & 1, ctl, body, crc8(covered) == frame[-1]


ma, mb = len(E.ca.sent), len(E.cb.sent)
d = connect(ka, 3, C.byref(SA.ops), None)
E.settle(20)
check("A connects to channel 3: open on both sides", ([e[1] for e in SA.events], [e[1] for e in SB.events]),
      ([OPEN], [OPEN]))
fa = [info(f) for f in rfc_frames(E.ca, ma)]
fb = [info(f) for f in rfc_frames(E.cb, mb)]
check("every frame's FCS good", all(x[4] for x in fa + fb), True)
check("A: SABM 0, then PN, SABM 6, MSC, MSC answer", [(x[0], x[2]) for x in fa][:5],
      [(0, 0x3F), (0, 0xEF), (6, 0x3F), (0, 0xEF), (0, 0xEF)])
check("B: UA 0, PN answer, UA 6, MSC, MSC answer", [(x[0], x[2]) for x in fb][:5],
      [(0, 0x73), (0, 0xEF), (6, 0x73), (0, 0xEF), (0, 0xEF)])
pn = fa[1][3]
check("A's PN: command for DLCI 6, credit flow asked, 1000 bytes, 7 credits",
      (pn[0], pn[1], pn[2], pn[3], struct.unpack_from("<H", pn, 6)[0], pn[9]), (0x83, 8 << 1 | 1, 6, 0xF0, 1000, 7))
check("B's PN answer agrees: credit flow on", (fb[1][3][0], fb[1][3][3]), (0x81, 0xE0))
check("C/R: A's commands 1, B's answers 1 too (it is the responder)", (fa[0][1], fb[0][1]), (1, 1))
db = SB.events[0][0]
check("credits on both sides", (C.c_uint32.from_address(d + L[2]).value, C.c_uint32.from_address(db + L[3]).value),
      (7, 7))

# ---- data -------------------------------------------------------------------------------------------------------
ma = len(E.ca.sent)
check("A sends", send(d, b"hello", 5), 0)
E.settle()
check("B gets it", SB.data, [(db, b"hello")])
check("in one UIH frame on DLCI 6", [(x[0], x[2], x[3]) for x in (info(f) for f in rfc_frames(E.ca, ma))],
      [(6, 0xEF, b"hello")])
SB.data.clear()
big = bytes((i * 3) & 0xFF for i in range(2500))
send(d, big, len(big))
E.settle(20)
check("2500 bytes: cut to 1000-byte frames, all of it arrives", (b"".join(x[1] for x in SB.data),
                                                                  [len(x[1]) for x in SB.data]),
      (big, [1000, 1000, 500]))
SB.data.clear()
for i in range(20):
    send(d, bytes([i]) * 10, 10)
E.settle(30)
check("20 frames: credits run out and come back, all in order", [x[1][0] for x in SB.data], list(range(20)))
SA.data.clear()
send(db, b"and back", 8)
E.settle()
check("B to A", SA.data, [(d, b"and back")])

# ---- the multiplexer, by hand to B -----------------------------------------------------------------------------
B_HANDLE = list(E.cb.links)[0]


def to_b(frame):
    """An RFCOMM frame to B on the session's channel (B's CID for it)."""
    mark = len(E.cb.sent)
    E.inject(E.cb, B_HANDLE, struct.pack("<HH", len(frame), B_CID) + frame)
    return [info(f) for f in rfc_frames(E.cb, mark)]


# B's CID of the session: the one A sends RFCOMM frames to
B_CID = struct.unpack_from("<H", [f for f in E.frames(E.ca, 0) if struct.unpack_from("<H", f, 2)[0] >= 0x40][0], 2)[0]


def mux_to_b(t, values):
    body = bytes([t, len(values) << 1 | 1]) + values
    head = bytes([0x03, 0xEF, len(body) << 1 | 1])
    return to_b(head + body + bytes([crc8(head[:2])]))


E.ca.deaf = True
got = mux_to_b(0x23, b"ping")
check("Test: echoed", [(x[0], x[3]) for x in got], [(0, bytes([0x21, 4 << 1 | 1]) + b"ping")])
got = mux_to_b(0x93, bytes([6 << 2 | 3, 0x07]))
check("Remote Port Negotiation: answered", [x[3][0] for x in got], [0x91])
got = mux_to_b(0xFF, b"")
check("an unknown command: Non Supported Command naming it", [x[3] for x in got], [bytes([0x11, 3, 0xFF])])
mux_to_b(0x63, b"")
mark = len(E.cb.sent)
check("Flow Control Off: B holds its data", (send(db, b"held", 4), rfc_frames(E.cb, mark)), (0, []))
got = mux_to_b(0xA3, b"")
check("Flow Control On: it goes", [x[3] for x in got if x[0] == 6], [b"held"])
mark = len(E.cb.sent)
bad = bytes([0x03, 0xEF, 3]) + bytes([0x21, 1]) + bytes([0x00])
dropped = C.c_uint32.in_dll(lib, "ubt_rfc_dropped").value
to_b(bad)
check("a frame with a bad FCS: dropped", C.c_uint32.in_dll(lib, "ubt_rfc_dropped").value - dropped, 1)
sabm = bytes([(20 << 2) | 3, 0x3F, 1])
got = to_b(sabm + bytes([crc8(sabm)]))
check("SABM for a channel nobody serves (10): DM", [(x[0], x[2]) for x in got], [(20, 0x1F)])
E.ca.deaf = False

# ---- refusals, closing ------------------------------------------------------------------------------------------
SA.events.clear()
d2 = connect(ka, 5, C.byref(SA.ops), None)
E.settle(20)
check("connecting to a channel nobody serves: refused", [e[1] for e in SA.events], [REFUSED])
check("channel 0 or 31: not tried", (connect(ka, 0, C.byref(SA.ops), None), connect(ka, 31, C.byref(SA.ops), None)),
      (None, None))
SA.events.clear()
SB.events.clear()
close(d)
E.settle()
check("A closes: DISC, UA, closed on both sides", ([e[1] for e in SA.events], [e[1] for e in SB.events]),
      ([CLOSED], [CLOSED]))
SA.events.clear()
SB.events.clear()
d = connect(ka, 3, C.byref(SA.ops), None)
E.settle(20)
check("again over the same session", ([e[1] for e in SA.events], [e[1] for e in SB.events]), ([OPEN], [OPEN]))
SA.events.clear()
E.disconnect(ka, 0x13)
E.settle()
check("the link goes: the channel closed", [e[1] for e in SA.events], [CLOSED])

# ---- everything given back ------------------------------------------------------------------------------------------
E.remove(E.a)
E.remove(E.b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_rfcomm: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

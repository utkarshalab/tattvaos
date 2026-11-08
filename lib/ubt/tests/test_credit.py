"""L2CAP credit-based channels (l2cap/credit.asm): LE Credit Based and
Enhanced Credit Based Flow Control modes between two of our stacks on the
virtual radio, on an LE link and on BR/EDR, with requests, frames and
broken peers made by hand.

usage: python3 test_credit.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import (Env, Chan, Conn, Cred, EV_OPEN, EV_CLOSED, EV_REFUSED, EV_RECONF, WHY_MODE,  # noqa: E402
                       BASIC, LE_CREDITS, ECRED)

E = Env(sys.argv[1])
check, SA, SB, ca, cb = E.check, E.SA, E.SB, E.ca, E.cb
LE_SIG = 5
E.server(0x0080, LE_CREDITS, C.byref(SB.ops), None)
E.server(0x0081, ECRED, C.byref(SB.ops), None)
E.server(0x0082, ECRED, C.byref(SB.ops), None)
E.server(0x1001, BASIC, C.byref(SB.ops), None)

la, lb = E.le_link()
LA, LB = Conn.from_address(la), Conn.from_address(lb)
check("an LE link", (LA.type, LA.role, LB.role), (1, 0, 1))


def cred(ch):
    return Cred.from_address(Chan.from_address(ch).cred)


def events(side, ch):
    return [e[1:] for e in side.events if e[0] == ch]


def peer_of(ch):
    """B's channel for A's channel: the one whose CID A sends to."""
    dcid = Chan.from_address(ch).dcid
    for c, ev, _ in SB.events:
        if ev == EV_OPEN and Chan.from_address(c).scid == dcid:
            return c
    return None


def to(ctrl, conn, code, ident, data, cid=LE_SIG):
    """A signalling command to a controller's host as if from the peer → what it answers."""
    cmd = struct.pack("<BBH", code, ident, len(data)) + bytes(data)
    mark = len(ctrl.sent)
    E.radio.inject(ctrl, conn.handle, 2, struct.pack("<HH", len(cmd), cid) + cmd)
    E.settle()
    return E.sig(ctrl, mark, cid)


def kframe(ctrl, conn, cid, payload):
    mark = len(ctrl.sent)
    E.inject(ctrl, conn.handle, struct.pack("<HH", len(payload), cid) + payload)
    return mark


def open_le(psm=0x0080):
    ch = E.l2connect(la, psm, LE_CREDITS, C.byref(SA.ops), None)
    E.settle()
    return ch


# ---- what does not go on LE ---------------------------------------------------------------------
check("basic mode on an LE link: not even tried", E.l2connect(la, 0x1001, BASIC, C.byref(SA.ops), None), None)

# ---- an LE credit-based channel -----------------------------------------------------------------
mark_a, mark_b = len(ca.sent), len(cb.sent)
ch = open_le()
req = [s for s in E.sig(ca, mark_a, LE_SIG) if s[0] == 0x14]
check("LE Credit Based Connection Request: SPSM, our MTU, MPS, credits, CID",
      [r[2] for r in req], [struct.pack("<HHHHH", 0x80, 1017, 247, 10, 0x40)])
rsp = [s for s in E.sig(cb, mark_b, LE_SIG) if s[0] == 0x15]
check("B's answer: its CID, MTU, MPS, credits, success", [(r[1], r[2]) for r in rsp],
      [(req[0][1], struct.pack("<HHHHH", 0x40, 1017, 247, 10, 0))])
chb = peer_of(ch)
check("open on both sides", (events(SA, ch), events(SB, chb)), ([(EV_OPEN, 0)], [(EV_OPEN, 0)]))
A, B, CA, CB = Chan.from_address(ch), Chan.from_address(chb), cred(ch), cred(chb)
check("what A knows of B: its CID, MTU, MPS, credits", (A.dcid, A.omtu, CA.mps, CA.tx_credits, A.mode),
      (0x40, 1017, 247, 10, LE_CREDITS))

mark = len(ca.sent)
check("A sends 100 bytes", E.l2send(ch, bytes(range(100)), 100), 0)
E.settle()
check("B gets them", SB.data[-1:], [(chb, bytes(range(100)))])
f = E.on_cid(ca, A.dcid, mark)
check("one K-frame: the SDU's length, then the data", [x[4:6] for x in f], [struct.pack("<H", 100)])
check("one credit used on each side", (CA.tx_credits, CB.rx_credits), (9, 9))

SB.data.clear()
mark, mark_b = len(ca.sent), len(cb.sent)
big = bytes((i * 7) & 0xFF for i in range(1017))
E.l2send(ch, big, 1017)
E.settle()
f = E.on_cid(ca, A.dcid, mark)
check("1017 bytes: K-frames of B's MPS, the first with the length", [len(x) - 4 for x in f], [247, 247, 247, 247, 31])
check("B puts it back together", SB.data, [(chb, big)])
gave = [s for s in E.sig(cb, mark_b, LE_SIG) if s[0] == 0x16]
check("half its credits used: B gives them back, for its CID", [g[2] for g in gave], [struct.pack("<HH", B.scid, 5)])
check("and the two sides agree on what is left", (CA.tx_credits, CB.rx_credits), (9, 9))
check("more than B's MTU: not sent", E.l2send(ch, bytes(1018), 1018), -2)
SA.data.clear()
E.l2send(chb, b"and back", 8)
E.settle()
check("B to A", SA.data, [(ch, b"and back")])

# ---- waiting for credits --------------------------------------------------------------------------
SB.data.clear()
for i in range(25):
    E.l2send(ch, bytes([i]) * 30, 30)
check("25 SDUs at once: as many go as A has credits, the rest wait", (CA.tx_credits, CA.txq != 0), (0, True))
E.settle()
check("credits come back: all 25 arrive, in order", ([d[1][0] for d in SB.data], CA.txq, CA.txq_tail),
      (list(range(25)), 0, 0))

# ---- K-frames made by hand, to A --------------------------------------------------------------------
cb.deaf = True
SA.data.clear()
kframe(ca, LA, A.scid, struct.pack("<H", 300) + bytes([1]) * 100)
kframe(ca, LA, A.scid, bytes([2]) * 150)
check("an SDU in pieces: nothing yet", (SA.data, CA.sdu_got, CA.sdu_len), ([], 250, 300))
kframe(ca, LA, A.scid, bytes([3]) * 50)
check("then all of it", SA.data, [(ch, bytes([1]) * 100 + bytes([2]) * 150 + bytes([3]) * 50)])
SA.data.clear()
kframe(ca, LA, A.scid, struct.pack("<H", 0))
check("an empty SDU is an SDU", SA.data, [(ch, b"")])
before = CA.tx_credits
to(ca, LA, 0x16, 60, struct.pack("<HH", A.dcid, 5))
check("Flow Control Credit: 5 more", CA.tx_credits, before + 5)
to(ca, LA, 0x16, 61, struct.pack("<HH", 0x7E, 5))
check("credits for no channel: nothing", CA.tx_credits, before + 5)

cb.deaf = False                                         # B hears again: it answers A closing


def breaks(label, frame_or_cmd):
    """Each rule broken by the peer: A closes the channel (asks B, who here hears)."""
    global ch, A, CA
    ch = open_le()
    A, CA = Chan.from_address(ch), cred(ch)
    mark = len(ca.sent)
    frame_or_cmd()
    asked = [s[0] for s in E.sig(ca, mark, LE_SIG)]
    check(label, (asked[-1:], events(SA, ch)[-1]), ([0x06], (EV_CLOSED, 0)))


breaks("a K-frame longer than our MPS: the channel goes",
       lambda: kframe(ca, LA, A.scid, struct.pack("<H", 400) + bytes(246)))
breaks("an SDU longer than our MTU: the channel goes",
       lambda: kframe(ca, LA, A.scid, struct.pack("<H", 1018) + bytes(10)))
breaks("a first K-frame without its length: the channel goes", lambda: kframe(ca, LA, A.scid, b"\x05"))
breaks("more data than the SDU said: the channel goes",
       lambda: (kframe(ca, LA, A.scid, struct.pack("<H", 20) + bytes(10)), kframe(ca, LA, A.scid, bytes(11))))


def no_credit():
    CA.rx_credits = 0
    kframe(ca, LA, A.scid, struct.pack("<H", 1) + b"x")


breaks("a K-frame without a credit: the channel goes", no_credit)
breaks("credits past 65535: the channel goes", lambda: to(ca, LA, 0x16, 62, struct.pack("<HH", A.dcid, 0xFFFF)))

# ---- refusals -----------------------------------------------------------------------------------------
SA.events.clear()
ch_x = E.l2connect(la, 0x0099, LE_CREDITS, C.byref(SA.ops), None)
E.settle()
check("no server on that SPSM: refused, result 2", SA.events, [(ch_x, EV_REFUSED, 2)])
SA.events.clear()
ch_x = E.l2connect(la, 0x0081, LE_CREDITS, C.byref(SA.ops), None)
E.settle()
check("a server for the other credit mode: the same", SA.events, [(ch_x, EV_REFUSED, 2)])
ca.deaf = True                                          # B's answers only


def le_req(ident, mtu, mps, scid, psm=0x0080):
    r = to(cb, LB, 0x14, ident, struct.pack("<HHHHH", psm, mtu, mps, 10, scid))
    return [struct.unpack("<HHHHH", x[2])[4] for x in r if x[0] == 0x15]


check("a CID outside the LE dynamic range: result 9", le_req(70, 100, 100, 0x0030) + le_req(71, 100, 100, 0x0080),
      [9, 9])
check("a CID already in use: result 10", (le_req(72, 100, 100, 0x0070), le_req(73, 100, 100, 0x0070)), ([0], [10]))
check("an MTU or MPS under 23: result 11", le_req(74, 22, 100, 0x0071) + le_req(75, 100, 22, 0x0072), [11, 11])
ca.deaf = False

# ---- enhanced credit based, on LE ------------------------------------------------------------------------
SA.events.clear()
SB.events.clear()
mark_a, mark_b = len(ca.sent), len(cb.sent)
chans = (C.c_void_p * 5)()
check("three enhanced channels asked for at once", E.connect_ecred(la, 0x0081, 3, C.byref(SA.ops), None, chans), 3)
E.settle()
three = list(chans[:3])
req = [s for s in E.sig(ca, mark_a, LE_SIG) if s[0] == 0x17]
scids = [Chan.from_address(c).scid for c in three]
check("one Credit Based Connection Request with the three CIDs",
      [r[2] for r in req], [struct.pack("<HHHH", 0x81, 1017, 247, 10) + struct.pack("<3H", *scids)])
rsp = [s for s in E.sig(cb, mark_b, LE_SIG) if s[0] == 0x18]
check("one answer: success, a CID for each", [struct.unpack_from("<HHHH", r[2])[3] for r in rsp] +
      [len(r[2]) for r in rsp], [0, 14])
check("all three open on both sides", ([e[1] for e in SA.events], [e[1] for e in SB.events]),
      ([EV_OPEN] * 3, [EV_OPEN] * 3))
SB.data.clear()
for i, c in enumerate(three):
    E.l2send(c, bytes([0x30 + i]) * 200, 200)
E.settle()
check("each carries its own data", sorted((d[1][0], d[0] == peer_of(three[d[1][0] - 0x30])) for d in SB.data),
      [(0x30, True), (0x31, True), (0x32, True)])

ca.deaf = True                                          # B's answers only


def ecred_req(ident, cids, mtu=100, mps=100, psm=0x0081):
    r = [x for x in to(cb, LB, 0x17, ident, struct.pack("<HHHH", psm, mtu, mps, 10) + struct.pack(f"<{len(cids)}H", *cids))
         if x[0] == 0x18]
    return [(struct.unpack_from("<H", x[2], 6)[0], list(struct.unpack_from(f"<{(len(x[2]) - 8) // 2}H", x[2], 8)))
            for x in r]


got = ecred_req(80, [0x60, 0x70, 0x30])
check("one CID new, one taken, one outside the range: two refused, the result says why",
      (got[0][0] in (9, 10), got[0][1][0] != 0, got[0][1][1:]), (True, True, [0, 0]))
check("six CIDs: all refused, invalid parameters", ecred_req(81, list(range(0x61, 0x67))), [(0x0C, [0] * 5)])
check("an MTU under 64: all refused", ecred_req(82, [0x68], mtu=63), [(0x0C, [0])])
check("no such SPSM: all refused", ecred_req(83, [0x69], psm=0x00F1), [(2, [0])])
ca.deaf = False

# ---- reconfiguration ------------------------------------------------------------------------------------------
c0 = three[0]
b0 = peer_of(c0)
SA.events.clear()
mark_a = len(ca.sent)
check("a larger MTU asked for", E.reconfigure(c0, 2000), 0)
E.settle()
req = [s for s in E.sig(ca, mark_a, LE_SIG) if s[0] == 0x19]
check("Credit Based Reconfigure Request: MTU, MPS, our CID", [r[2] for r in req],
      [struct.pack("<HHH", 2000, 247, Chan.from_address(c0).scid)])
check("accepted: A takes 2000 now, B knows it", (events(SA, c0), Chan.from_address(c0).imtu, Chan.from_address(b0).omtu),
      ([(EV_RECONF, 0)], 2000, 2000))
SA.data.clear()
check("so B may send 1500 bytes", E.l2send(b0, bytes(1500), 1500), 0)
E.settle()
check("and A takes them", [(d[0], len(d[1])) for d in SA.data], [(c0, 1500)])
check("smaller than now: not asked", E.reconfigure(c0, 1999), -2)
check("on an LE credit-based channel: not asked", E.reconfigure(open_le(), 2000), -2)

ca.deaf = True


def reconf(ident, mtu, mps, cids):
    return [struct.unpack("<H", x[2])[0] for x in to(cb, LB, 0x19, ident, struct.pack("<HH", mtu, mps) +
                                                     struct.pack(f"<{len(cids)}H", *cids)) if x[0] == 0x1A]


s1, s2 = (Chan.from_address(c).scid for c in three[1:])
check("a smaller MTU: result 1", reconf(90, 1000, 247, [s1]), [1])
check("a smaller MPS for two channels: result 2", reconf(91, 1017, 100, [s1, s2]), [2])
check("a CID that is no channel: result 3", reconf(92, 1100, 247, [s1, 0x7D]), [3])
check("an MTU under 64: result 4", reconf(93, 50, 247, [s1]), [4])
check("nothing changed by those", [Chan.from_address(peer_of(c)).omtu for c in three[1:]], [1017, 1017])
check("a smaller MPS for one channel, a larger MTU: fine", reconf(94, 1100, 100, [s1]), [0])
ca.deaf = False

# ---- enhanced credit based, on BR/EDR -----------------------------------------------------------------------------
ka, kb = E.link()
KA = Conn.from_address(ka)
check("a BR/EDR peer that says it does enhanced credit based", KA.ext_features & 0x400, 0x400)
SA.events.clear()
SB.events.clear()
SB.data.clear()
mark_a = len(ca.sent)
check("two on BR/EDR", E.connect_ecred(ka, 0x0082, 2, C.byref(SA.ops), None, chans), 2)
E.settle()
two = list(chans[:2])
check("asked on the BR/EDR signalling channel, both open",
      ([s[0] for s in E.sig(ca, mark_a, 1) if s[0] == 0x17], [e[1] for e in SB.events]), ([0x17], [EV_OPEN] * 2))
E.l2send(two[1], b"over BR/EDR", 11)
E.settle()
check("data over them", [d[1] for d in SB.data], [b"over BR/EDR"])
KA.ext_features = 0x0B8
SA.events.clear()
n = E.connect_ecred(ka, 0x0082, 2, C.byref(SA.ops), None, chans)
check("to a peer that does not: both refused, not asked", [e[1:] for e in SA.events], [(EV_REFUSED, WHY_MODE)] * 2)
KA.ext_features = 0x4B8
ca.deaf = True
r = to(cb, Conn.from_address(kb), 0x14, 99, struct.pack("<HHHHH", 0x80, 100, 100, 10, 0x50), cid=1)
check("LE Credit Based Connection on BR/EDR: not understood", r, [(0x01, 99, b"\x00\x00")])
ca.deaf = False

# ---- closing, and everything given back ----------------------------------------------------------------------------
SA.events.clear()
E.l2disconnect(three[2])
E.settle()
check("an enhanced channel closed", events(SA, three[2]), [(EV_CLOSED, 0)])
E.disconnect(la, 0x13)
E.disconnect(ka, 0x13)
E.settle()
E.remove(E.a)
E.remove(E.b)
check("every block given back", sorted(E.live.values()), [])

print(f"test_credit: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

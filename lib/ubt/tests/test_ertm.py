"""L2CAP Enhanced Retransmission and Streaming modes (l2cap/ertm.asm): two
of our stacks on the virtual radio, frames checked bit by bit, losses,
polls, rejects, busy peers and broken ones made by hand.

usage: python3 test_ertm.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import (Env, Chan, Conn, Ertm, EV_OPEN, EV_CLOSED, EV_REFUSED, WHY_MODE,  # noqa: E402
                       ERTM, STREAMING, BASIC, parse, iframe, sframe, crc16)

E = Env(sys.argv[1])
check, SA, SB, ca, cb = E.check, E.SA, E.SB, E.ca, E.cb
RR, REJ, RNR, SREJ = 0, 1, 2, 3

ka, kb = E.link()
A_conn, B_conn = Conn.from_address(ka), Conn.from_address(kb)
check("the peer says it does ERTM, streaming and FCS", A_conn.ext_features & 0xB8, 0xB8)
E.server(0x1101, ERTM, C.byref(SB.ops), None)
E.server(0x1103, STREAMING, C.byref(SB.ops), None)
E.server(0x1105, BASIC, C.byref(SB.ops), None)

# ---- opening an ERTM channel ---------------------------------------------------------------
mark_a, mark_b = len(ca.sent), len(cb.sent)
ch_a = E.l2connect(ka, 0x1101, ERTM, C.byref(SA.ops), None)
E.settle()
check("open on both sides", ([e[1] for e in SA.events], [e[1] for e in SB.events]), ([EV_OPEN], [EV_OPEN]))
ch_b = SB.events[-1][0]
A, B = Chan.from_address(ch_a), Chan.from_address(ch_b)
conf_a = [s for s in E.sig(ca, mark_a) if s[0] == 0x04][0][2]
check("A's Configuration Request: MTU, then RFC (ERTM, window 10, 3 tries, timeouts left to B, 1000 bytes)",
      conf_a[4:], struct.pack("<BBH", 1, 2, 1017) + struct.pack("<BBBBBHHH", 4, 9, 3, 10, 3, 0, 0, 1000))
rsp_b = [s for s in E.sig(cb, mark_b) if s[0] == 0x05][0][2]
check("B's answer: success, with the timeouts it wants (2 s, 12 s)",
      rsp_b[4:], struct.pack("<HBBBBBHHH", 0, 4, 9, 3, 10, 3, 2000, 12000, 1000))
EA, EB = Ertm.from_address(A.ertm), Ertm.from_address(B.ertm)
check("what each side uses: the other's window, tries, payload size; the timeouts",
      (EA.txwin, EA.maxtx, EA.mps, EA.retrans_ms, EA.monitor_ms, A.mode), (10, 3, 1000, 2000, 12000, ERTM))

# ---- data ----------------------------------------------------------------------------------------
mark = len(ca.sent)
check("A sends 100 bytes", E.l2send(ch_a, bytes(range(100)), 100), 0)
E.settle()
check("B gets them", SB.data[-1], (ch_b, bytes(range(100))))
f = [parse(x) for x in E.on_cid(ca, A.dcid, mark)]
check("one I-frame: TxSeq 0, unsegmented, a good FCS", [(x[1]["tx"], x[1]["sar"], x[3], len(x[2])) for x in f],
      [(0, 0, True, 100)])
back = [parse(x) for x in E.on_cid(cb, B.dcid, mark)]
check("B acknowledges with Receiver Ready, ReqSeq 1", [(x[1].get("s"), x[1]["req"], x[3]) for x in back], [(RR, 1, True)])
check("and A lets the frame go", (EA.unacked, EA.exp_ack, EA.sent[0], EA.retrans_at), (0, 1, 0, 0))
SB.data.clear()
mark = len(ca.sent)
big = bytes((i * 3) & 0xFF for i in range(1017))
E.l2send(ch_a, big, 1017)
E.settle()
f = [parse(x) for x in E.on_cid(ca, A.dcid, mark)]
check("1017 bytes: a start (its SDU length, 998 bytes) and an end (19)",
      [(x[1]["sar"], len(x[2])) for x in f], [(1, 1000), (2, 19)])
check("the start's first two bytes: the whole length", f[0][2][:2], struct.pack("<H", 1017))
check("B puts it back together", SB.data, [(ch_b, big)])
check("one byte too many for B's MTU", E.l2send(ch_a, bytes(1018), 1018), -2)
SA.data.clear()
E.l2send(ch_b, b"from B", 6)
E.settle()
check("B to A", SA.data, [(ch_a, b"from B")])

# ---- the window ---------------------------------------------------------------------------------
SB.data.clear()
cb.deaf = True
mark = len(ca.sent)
for i in range(15):
    E.l2send(ch_a, bytes([i]) * 20, 20)
E.settle()
sent = [parse(x) for x in E.on_cid(ca, A.dcid, mark)]
check("15 SDUs, B hears nothing: 10 go out (B's window), 5 wait", (len(sent), EA.unacked, EA.txq != 0), (10, 10, True))
cb.deaf = False
E.now[0] += 2100
E.settle()
polls = [parse(x) for x in E.on_cid(ca, A.dcid, mark) if parse(x)[1].get("s") == RR]
check("no acknowledgement in 2 s: A polls (RR with P)", [(p[1]["p"], p[1]["req"]) for p in polls][:1], [(1, 1)])
check("B answers with F, A sends everything again and the rest: all 15 arrive, in order",
      ([d[1][0] for d in SB.data], EA.unacked, EA.txq), (list(range(15)), 0, 0))

# ---- a lost frame: Reject -------------------------------------------------------------------------
SB.data.clear()
lost = {"n": 0}
orig = ca.acl


def lose_third_frame(pkt):
    w = struct.unpack_from("<H", pkt)[0]
    if (w >> 12) & 3 == 2:                              # a frame starts
        lost["n"] += 1
    if lost["n"] == 3:
        return                                          # all of the third frame's pieces lost
    orig(pkt)


ca.acl = lose_third_frame
mark_b = len(cb.sent)
for i in range(6):
    E.l2send(ch_a, bytes([0x40 + i]) * 10, 10)
E.settle()
ca.acl = orig
E.settle()
rej = [parse(x) for x in E.on_cid(cb, B.dcid, mark_b) if parse(x)[1].get("s") == REJ]
check("a frame lost: B rejects once, from the missing one", [r[1]["req"] for r in rej], [(EB.exp_tx - 4) % 64])
check("A sends again from there: all six arrive, in order", [d[1][0] for d in SB.data], [0x40 + i for i in range(6)])

# ---- frames made by hand, to A --------------------------------------------------------------------
H = A_conn.handle


def to_a(frame):
    mark = len(ca.sent)
    E.inject(ca, H, frame)
    return [parse(x) for x in E.on_cid(ca, A.dcid, mark)]


cb.deaf = True                                          # B keeps quiet: only A's answers
SA.data.clear()
exp = EA.exp_tx
dropped = C.c_uint32.in_dll(E.lib, "l2cap_dropped").value
to_a(iframe(A.scid, exp, EA.next_tx, payload=b"bad", fcs=False))
check("a wrong FCS: dropped, not delivered", (C.c_uint32.in_dll(E.lib, "l2cap_dropped").value - dropped, SA.data, EA.exp_tx),
      (1, [], exp))
out = to_a(iframe(A.scid, exp, EA.next_tx, payload=b"good"))
check("the right one: delivered, acknowledged", (SA.data, [(o[1]["s"], o[1]["req"]) for o in out]),
      ([(ch_a, b"good")], [(RR, (exp + 1) % 64)]))
SA.data.clear()
out = to_a(iframe(A.scid, exp, EA.next_tx, payload=b"good"))
check("the same again: a duplicate, dropped but acknowledged", (SA.data, [o[1]["s"] for o in out]), ([], [RR]))
out = to_a(sframe(A.scid, RR, EA.next_tx, p=1))
check("polled: Receiver Ready with F", [(o[1]["s"], o[1]["f"]) for o in out], [(RR, 1)])
to_a(sframe(A.scid, RNR, EA.next_tx))
mark = len(ca.sent)
E.l2send(ch_a, b"wait", 4)
E.settle()
check("Receiver Not Ready: A holds back", (E.on_cid(ca, A.dcid, mark), EA.txq != 0), ([], True))
out = to_a(sframe(A.scid, RR, EA.next_tx))
check("Receiver Ready: it goes", ([o[2] for o in out if "tx" in o[1]], EA.txq), ([b"wait"], 0))
held = EA.next_tx
E.l2send(ch_a, b"one", 3)
E.l2send(ch_a, b"two", 3)
E.settle()
out = to_a(sframe(A.scid, SREJ, (held + 1) % 64))
check("Selective Reject: just that frame again", [(o[1]["tx"], o[2]) for o in out if "tx" in o[1]], [((held + 1) % 64, b"two")])
out = to_a(sframe(A.scid, REJ, held))
check("Reject: everything from it again", [o[2] for o in out if "tx" in o[1]], [b"one", b"two"])
to_a(sframe(A.scid, RR, EA.next_tx))                    # all acknowledged
check("acknowledged: nothing kept", (EA.unacked, sum(1 for s in EA.sent if s)), (0, 0))
cb.deaf = False                                         # B may hear A again: nothing is outstanding
mark_sig = len(ca.sent)
to_a(sframe(A.scid, RR, (EA.next_tx + 5) % 64))
check("acknowledging frames never sent: A closes the channel",
      [s[0] for s in E.sig(ca, mark_sig)], [0x06])
E.settle()
check("closed on both sides", ([e[1] for e in SA.events][-1], [e[1] for e in SB.events][-1]), (EV_CLOSED, EV_CLOSED))

# ---- MaxTransmit: a peer that never answers ---------------------------------------------------------
SA.events.clear()
ch_a = E.l2connect(ka, 0x1101, ERTM, C.byref(SA.ops), None)
E.settle()
A = Chan.from_address(ch_a)
EA = Ertm.from_address(A.ertm)
cb.deaf = True
mark = len(ca.sent)
E.l2send(ch_a, b"x", 1)
E.settle()
for _ in range(4):
    E.now[0] += 12100
    E.settle()
polls = [parse(x) for x in E.on_cid(ca, A.dcid, mark) if parse(x)[1].get("s") == RR and parse(x)[1]["p"]]
check("polled MaxTransmit (3) times, then the channel given up",
      (len(polls), [s[0] for s in E.sig(ca, mark)]), (3, [0x06]))
E.now[0] += 11000
E.settle()
check("closed (B never answers that either)", [e[1] for e in SA.events if e[0] == ch_a][-1], EV_CLOSED)
cb.deaf = False
stale = SB.events[-1][0]                                # B never heard: it closes its side itself
E.l2disconnect(stale)
E.settle()
check("B's side, closed by B: A no longer knows the channel and says so, B lets it go",
      [e[1] for e in SB.events if e[0] == stale][-1], EV_CLOSED)

# ---- streaming ------------------------------------------------------------------------------------------
SA.events.clear()
SB.events.clear()
SB.data.clear()
ch_s = E.l2connect(ka, 0x1103, STREAMING, C.byref(SA.ops), None)
E.settle()
check("a streaming channel open", ([e[1] for e in SA.events], [e[1] for e in SB.events]), ([EV_OPEN], [EV_OPEN]))
S = Chan.from_address(ch_s)
sb = SB.events[-1][0]
lost["n"] = 0
ca.acl = lose_third_frame
mark_b = len(cb.sent)
for i in range(5):
    E.l2send(ch_s, bytes([0x60 + i]) * 8, 8)
E.settle()
ca.acl = orig
check("one frame lost: that SDU is gone, the others arrive", [d[1][0] for d in SB.data if d[0] == sb],
      [0x60, 0x61, 0x63, 0x64])
check("and nothing comes back: no acknowledgements in streaming mode", E.on_cid(cb, Chan.from_address(sb).dcid, mark_b), [])

# ---- modes that do not fit -------------------------------------------------------------------------------
A_conn.ext_features = 0x80                              # as if the peer only did basic mode
SA.events.clear()
ch_x = E.l2connect(ka, 0x1101, ERTM, C.byref(SA.ops), None)
E.settle()
check("ERTM to a peer that cannot: refused, not asked", SA.events, [(ch_x, EV_REFUSED, WHY_MODE)])
A_conn.ext_features = 0x4B8
cb.deaf = False
ca.deaf = True                                          # only B's answers now
mark = len(cb.sent)
cmd = struct.pack("<BBHHH", 0x02, 70, 4, 0x1101, 0x0070)
E.radio.inject(cb, B_conn.handle, 2, struct.pack("<HH", len(cmd), 1) + cmd)
E.settle()
new = [s for s in E.sig(cb, mark) if s[0] == 0x03][0]
cid = struct.unpack_from("<H", new[2])[0]
mark = len(cb.sent)
cmd = struct.pack("<BBHHHBBH", 0x04, 71, 8, cid, 0, 1, 2, 672)
E.radio.inject(cb, B_conn.handle, 2, struct.pack("<HH", len(cmd), 1) + cmd)
E.settle()
rsp = [s for s in E.sig(cb, mark) if s[0] == 0x05][0][2]
check("an ERTM server asked for basic (no RFC): unacceptable, with its RFC",
      (struct.unpack_from("<H", rsp, 4)[0], rsp[6:9]), (1, bytes([4, 9, 3])))
ca.deaf = False

# ---- the FCS itself ------------------------------------------------------------------------------------------
check("the CRC-16 the frames above were checked with is the spec's (0x8005 reflected, from 0)",
      crc16(b"123456789"), 0xBB3D)

# ---- everything given back ------------------------------------------------------------------------------------
E.disconnect(ka, 0x13)
E.settle()
E.remove(E.a)
E.remove(E.b)
check("every block given back", sorted(E.live.values()), [])

print(f"test_ertm: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

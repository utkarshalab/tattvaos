"""A fuzzer for every parser: HCI events, ACL reassembly, L2CAP signalling
(BR/EDR and LE), basic, ERTM and credit-based channels, SMP, ATT, SDP and
RFCOMM. Real traffic is recorded first; then each round takes a recorded
packet, damages it (bits flipped, bytes changed, cut, made longer, length
fields changed) and gives it to the stack. Nothing may crash, the stack
must still work after, and every block it took must come back.

usage: python3 test_fuzz.py path/to/ubt.so [rounds [seed]]   (default 4000, 2026)
"""
import ctypes as C
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env, Ops, BASIC, ERTM, LE_CREDITS  # noqa: E402

ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
E = Env(sys.argv[1])
check, lib, a, b, ca, cb = E.check, E.lib, E.a, E.b, E.ca, E.cb
rng = random.Random(int(sys.argv[3]) if len(sys.argv) > 3 else 2026)
fn = E.fn
RAND = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_uint32)(
    lambda p, n: (C.memmove(p, bytes(rng.getrandbits(8) for _ in range(n)), n), 0)[1])
C.c_void_p.in_dll(lib, "ubt_random_fn").value = C.cast(RAND, C.c_void_p).value
G = list((C.c_uint32 * 16).in_dll(lib, "ubt_gap_layout"))
for ad in (a, b):
    C.c_uint8.from_address(ad + G[1]).value = 3
    C.c_uint8.from_address(ad + G[2]).value = 1


def mutate(data):
    d = bytearray(data)
    for _ in range(rng.randint(1, 4)):
        op = rng.randrange(6)
        if op == 0 and d:                                  # a bit
            i = rng.randrange(len(d))
            d[i] ^= 1 << rng.randrange(8)
        elif op == 1 and d:                                # a byte
            d[rng.randrange(len(d))] = rng.choice((0, 0xFF, 0x7F, 0x80, rng.randrange(256)))
        elif op == 2 and len(d) > 1:                       # cut
            del d[rng.randrange(1, len(d)):]
        elif op == 3:                                      # longer
            d += bytes(rng.randrange(256) for _ in range(rng.randint(1, 40)))
        elif op == 4 and len(d) >= 4:                      # a length field (L2CAP or ACL)
            at = rng.choice((0, 2)) if len(d) > 4 else 0
            struct.pack_into("<H", d, at, rng.choice((0, 1, len(d), len(d) + 1, 0xFFFF, rng.randrange(65536))))
        elif op == 5 and len(d) > 2:                       # a run of bytes the same
            i = rng.randrange(len(d))
            d[i:i + 8] = bytes([rng.randrange(256)]) * min(8, len(d) - i)
    return bytes(d)


# ---- record real traffic: every layer on both links --------------------------------------------------------
fn("ubt_sdp_init", None)()
fn("ubt_rfcomm_init", None)()
users = Ops(0, 0)
fn("ubt_rfcomm_server", C.c_int32, C.c_uint32, C.c_void_p, C.c_void_p)(3, C.byref(users), None)
for psm, mode in ((0x1001, BASIC), (0x1101, ERTM), (0x0080, LE_CREDITS)):
    E.server(psm, mode, C.byref(users), None)
fn("ubt_br_enable", None, C.c_void_p)(a)
fn("ubt_br_enable", None, C.c_void_p)(b)
event_mark = len(ca.cmd_log)
ka, kb = E.link()
la, lb = E.le_link()
rec_a = len(ca.sent)
E.l2connect(ka, 0x1001, BASIC, C.byref(users), None)
chE = E.l2connect(ka, 0x1101, ERTM, C.byref(users), None)
chL = E.l2connect(la, 0x0080, LE_CREDITS, C.byref(users), None)
E.settle()
E.l2send(chE, b"ertm data", 9)
E.l2send(chL, b"credit data", 11)
fn("ubt_sdp_query", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32, C.c_uint32)(ka, b"\x00\x01", 1, 0, 0xFFFF)
fn("ubt_rfcomm_connect", C.c_void_p, C.c_void_p, C.c_uint32, C.c_void_p, C.c_void_p)(ka, 3, C.byref(users), None)
fn("ubt_gatt_services", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)(la, None, 0)
fn("ubt_pair", C.c_int32, C.c_void_p)(la)
E.settle(30)
corpus = [(h, pb, d) for h, pb, d in ca.sent[rec_a:]]
frames = E.frames(ca, rec_a)
check("traffic recorded on every layer", len({struct.unpack_from("<H", f, 2)[0] for f in frames}) >= 5, True)

# events the controllers sent, rebuilt for replay
events = []
for c in (ca, cb):
    events += [bytes([0x0E, 4, 1]) + struct.pack("<H", op) + b"\x00" for op, _ in c.cmd_log[:20]]
events += [bytes([0x3E, 19, 1, 0]) + struct.pack("<HBB", 0x50, 1, 0) + bytes(6) + struct.pack("<HHHB", 24, 0, 500, 0),
           bytes([0x02, 15, 1]) + bytes(14), bytes([0x2F, 255, 1]) + bytes(254), bytes([0x3E, 12, 2, 1, 0, 0]) + bytes(6) + b"\x00\xC0",
           bytes([0x3E, 30, 0x0D, 1]) + bytes(28), bytes([0x07, 255, 0]) + bytes(254), bytes([0x13, 5, 1, 0x40, 0, 1, 0]),
           bytes([0x05, 4, 0, 0x99, 0, 0x13]), bytes([0x08, 4, 0, 0x40, 0, 1]), bytes([0x3E, 13, 5, 0x40, 0]) + bytes(10),
           bytes([0x31, 6]) + bytes(6), bytes([0x33, 10]) + bytes(10), bytes([0x18, 23]) + bytes(23),
           bytes([0x0F, 4, 0, 1, 0x05, 0x04]), bytes([0x10, 1, 0x01])]

# ---- phase 1: damaged ACL and L2CAP to B, over the live links --------------------------------------------------
handles = {"br": None, "le": None}
for h, (peer, ph, kind) in cb.links.items():
    handles[kind] = h
sent = 0
le_handles = {hh for hh, (_, _, k) in ca.links.items() if k == "le"}
for i in range(ROUNDS):
    h, pb, data = rng.choice(corpus)
    bh = handles["le" if h in le_handles else "br"]
    if bh is None:
        continue
    flags = pb if rng.random() < 0.8 else rng.randrange(4)
    E.radio.inject(cb, bh, flags, mutate(data))
    sent += 1
    if i % 25 == 0:
        E.radio.run()
        E.service()
    if i % 400 == 0:
        E.now[0] += rng.choice((10, 1000, 31000))           # timers firing too
E.settle()
check(f"{sent} damaged packets to every layer: still alive", True, True)

# ---- phase 2: damaged events to A ------------------------------------------------------------------------------------
for i in range(ROUNDS // 2):
    ev = mutate(rng.choice(events))
    if len(ev) < 2:
        continue
    ev = ev[:2 + ev[1]] if len(ev) >= 2 + ev[1] else ev
    E.radio.inject_event(ca, ev[0], ev[2:2 + 255])
    if i % 25 == 0:
        E.radio.run()
        E.service()
E.settle()
check(f"{ROUNDS // 2} damaged events: still alive", True, True)

# ---- the stack still works: two new adapters on the same radio ----------------------------------------------
c, cc = E.radio.add(bytes([0xCC] * 6))
d, cd = E.radio.add(bytes([0xDD] * 6))
links = []
LINK = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(lambda ad, ev, conn: links.append((ad, ev, conn)))
acl_fn = list((C.c_uint32 * 30).in_dll(lib, "ubt_layout"))[26]
for ad in (c, d):
    C.c_void_p.from_address(ad + acl_fn + 8).value = C.cast(LINK, C.c_void_p).value
E.connect(c, bytes([0xDD] * 6))
E.settle()
kc = [conn for ad, ev, conn in links if ad == c and ev == 1]
ch = E.l2connect(kc[0], 0x1001, BASIC, C.byref(E.SA.ops), None) if kc else None
E.settle()
check("afterwards new adapters still link and open a channel", [e[1] for e in E.SA.events if e[0] == ch][-1:], [1])
E.remove(c)
E.remove(d)

# ---- everything given back --------------------------------------------------------------------------------------------------
E.remove(a)
E.remove(b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_fuzz: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

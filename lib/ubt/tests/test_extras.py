"""Out-of-band pairing (LE Secure Connections, LE legacy, BR/EDR),
Secure Connections Only on BR/EDR, LE privacy (our resolvable address,
its rotation, the controller's resolving list) and the built-in GATT
services (Device Information, Battery, Service Changed).

usage: python3 test_extras.py path/to/ubt.so
"""
import ctypes as C
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smp_ref as R  # noqa: E402
from l2cap_env import Env, Conn  # noqa: E402

E = Env(sys.argv[1])
check, a, b, ca, cb, lib = E.check, E.a, E.b, E.ca, E.cb, E.lib
G = list((C.c_uint32 * 16).in_dll(lib, "ubt_gap_layout"))
CONFIRM, PASSKEY, SHOW, PIN, PAIRED, JUST_WORKS = 4, 5, 6, 7, 8, 9
rev = lambda x: bytes(x[::-1])  # noqa: E731
fn = E.fn


class Pairing(C.Structure):
    _fields_ = [("conn", C.c_uint64), ("value", C.c_uint32), ("status", C.c_uint32), ("addr", C.c_uint8 * 6),
                ("addr_type", C.c_uint8), ("le", C.c_uint8)]


asked = {a: [], b: []}
GAP = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(
    lambda ad, kind, rec: asked[ad].append((kind, Pairing.from_address(rec).status)) if kind >= 4 else None)
for ad in (a, b):
    C.c_void_p.from_address(ad + G[0]).value = C.cast(GAP, C.c_void_p).value
rng = random.Random(3)


def give(p, n):
    C.memmove(p, bytes(rng.getrandbits(8) for _ in range(n)), n)
    return 0


RAND = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_uint32)(give)
C.c_void_p.in_dll(lib, "ubt_random_fn").value = C.cast(RAND, C.c_void_p).value
pair = fn("ubt_pair", C.c_int32, C.c_void_p)
confirm = fn("ubt_pair_confirm", None, C.c_void_p, C.c_uint32)
pin = fn("ubt_pair_pin", None, C.c_void_p, C.c_char_p, C.c_uint32)
oob_local = fn("ubt_smp_oob_local", C.c_int32, C.c_void_p)
oob_peer = fn("ubt_smp_oob_peer", C.c_int32, C.c_char_p, C.c_uint32, C.c_char_p, C.c_char_p)
oob_tk = fn("ubt_smp_oob_tk", C.c_int32, C.c_char_p, C.c_uint32, C.c_char_p)
oob_clear = fn("ubt_smp_oob_clear", None)
br_oob_local = fn("ubt_br_oob_local", C.c_int32, C.c_void_p, C.c_void_p)
br_oob_peer = fn("ubt_br_oob_peer", C.c_int32, C.c_char_p, C.c_char_p, C.c_char_p)
br_enable = fn("ubt_br_enable", None, C.c_void_p)
key_forget = fn("ubt_key_forget", None, C.c_void_p, C.c_char_p, C.c_uint32)
key_find = fn("ubt_key_find", C.c_uint64, C.c_void_p, C.c_char_p, C.c_uint32)
privacy = fn("ubt_le_privacy", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
own_type = fn("ubt_own_addr_type", C.c_uint32, C.c_void_p)
resolving = fn("ubt_le_resolving_sync", C.c_int32, C.c_void_p)
advertise = fn("ubt_le_advertise", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32, C.c_char_p, C.c_uint32)
adv_stop = fn("ubt_le_advertise_stop", C.c_int32, C.c_void_p)
scan = fn("ubt_le_scan", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
scan_stop = fn("ubt_le_scan_stop", C.c_int32, C.c_void_p)


def setup(ad, io, sc_only=0, legacy=0):
    C.c_uint8.from_address(ad + G[1]).value = io
    C.c_uint8.from_address(ad + G[2]).value = 1
    C.c_uint8.from_address(ad + G[3]).value = sc_only
    C.c_uint8.from_address(ad + G[15]).value = legacy


def forget():
    for addr in (E.A_ADDR, E.B_ADDR):
        key_forget(None, addr, 0)


def reset():
    for ad in (a, b):
        asked[ad].clear()
    answered.clear()


def smp(ctrl, start):
    return [f[4:] for f in E.frames(ctrl, start) if struct.unpack_from("<H", f, 2)[0] == 6]


def run(conns):
    for _ in range(20):
        E.settle()
        for ad, conn in conns:
            for i, (kind, _) in enumerate(asked[ad]):
                if kind in (CONFIRM, JUST_WORKS) and (ad, i) not in answered:
                    answered.add((ad, i))
                    confirm(conn, 1)


answered = set()

# ---- LE Secure Connections out of band ---------------------------------------------------------------------
la, lb = E.le_link()
LA = Conn.from_address(la)
setup(a, 3)
setup(b, 3)
mine = C.create_string_buffer(32)
check("B makes its out-of-band data", oob_local(mine), 0)
r_b, c_b = mine.raw[:16], mine.raw[16:]
check("A is given it", oob_peer(E.B_ADDR, 0, r_b, c_b), 0)
reset()
ma, mb = len(ca.sent), len(cb.sent)
pair(la)
run(((a, la), (b, lb)))
pa, pb = smp(ca, ma), smp(cb, mb)
req, rsp = pa[0], pb[0]
check("A's request says it has B's data, B's response says it has none", (req[2], rsp[2]), (1, 0))
check("no confirms, no questions: public keys, nonces, checks",
      ([p[0] for p in pa][:4], [p[0] for p in pb][:4], [k for k, _ in asked[a]]), ([1, 0x0C, 4, 0x0D], [2, 0x0C, 4, 0x0D], [PAIRED]))
pkb = [p[1:] for p in pb if p[0] == 0x0C][0]
check("B's public key is the one its commitment was made with",
      rev(R.f4(rev(pkb[:32]), rev(pkb[:32]), rev(r_b), 0)), c_b)
check("paired, authenticated with Secure Connections", ([s for k, s in asked[a] if k == PAIRED], LA.sec), ([0], 3))
E.disconnect(la, 0x13)
E.settle()
forget()
oob_clear()
bad = bytearray(c_b)
bad[0] ^= 1
oob_local(mine)
r_b, c_b = mine.raw[:16], mine.raw[16:]
oob_peer(E.B_ADDR, 0, r_b, bytes(bad))
la, lb = E.le_link()
reset()
pair(la)
run(((a, la), (b, lb)))
check("a commitment that does not match B's key: Confirm Value Failed",
      ([s for k, s in asked[a] if k == PAIRED], [s for k, s in asked[b] if k == PAIRED]), ([4], [4]))
oob_clear()
E.disconnect(la, 0x13)
E.settle()

# ---- LE legacy out of band (a TK) -----------------------------------------------------------------------------
setup(a, 3, legacy=1)
TK = bytes(range(0x60, 0x70))
oob_tk(E.B_ADDR, 0, TK)
oob_tk(E.A_ADDR, 0, TK)
la, lb = E.le_link()
LA = Conn.from_address(la)
reset()
ma, mb = len(ca.sent), len(cb.sent)
pair(la)
run(((a, la), (b, lb)))
pa, pb = smp(ca, ma), smp(cb, mb)
mconf, mrand = [p[1:] for p in pa if p[0] == 3][0], [p[1:] for p in pa if p[0] == 4][0]
c1 = rev(R.c1(rev(TK), rev(mrand), rev(pa[0]), rev(pb[0]), 0, 0, rev(E.A_ADDR), rev(E.B_ADDR)))
check("legacy with both holding the TK: confirms made from it", mconf, c1)
check("paired, authenticated (out of band)", ([s for k, s in asked[a] if k == PAIRED], LA.sec), ([0], 2))
oob_clear()
forget()
E.disconnect(la, 0x13)
E.settle()
oob_tk(E.B_ADDR, 0, TK)                                 # only A holds it
la, lb = E.le_link()
LA = Conn.from_address(la)
reset()
pair(la)
run(((a, la), (b, lb)))
check("only one side has the TK: Just Works instead", ([k for k, _ in asked[a]], LA.sec), ([JUST_WORKS, PAIRED], 1))
oob_clear()
forget()
E.disconnect(la, 0x13)
E.settle()
setup(a, 3)

# ---- BR/EDR out of band ------------------------------------------------------------------------------------------
br_enable(a)
br_enable(b)
E.settle()
setup(a, 1)
setup(b, 1)
data = C.create_string_buffer(64)
check("B's controller's out-of-band data read", br_oob_local(b, data), 0)
check("its P-256 C and R", (data.raw[32:48], data.raw[48:]), (cb.oob_c, cb.oob_r))
br_oob_peer(E.B_ADDR, data.raw[32:48], data.raw[48:])
ka, kb = E.link()
KA = Conn.from_address(ka)
reset()
mark = len(ca.cmd_log)
pair(ka)
run(((a, ka), (b, kb)))
io = [c[1] for c in ca.cmd_log[mark:] if c[0] == 0x042B][0]
check("A's IO capability says it has out-of-band data", io[7], 1)
check("A answered the controller with B's C and R", [c[1][38:] for c in ca.cmd_log[mark:] if c[0] == 0x0445],
      [cb.oob_c + cb.oob_r])
check("paired without a question, authenticated", ([k for k, _ in asked[a]], KA.sec), ([PAIRED], 3))
forget()
oob_clear()
E.disconnect(ka, 0x13)
E.settle()
br_oob_peer(E.B_ADDR, data.raw[32:48], bytes(16))
ka, kb = E.link()
reset()
pair(ka)
run(((a, ka), (b, kb)))
check("a wrong R: failed", [s for k, s in asked[a] if k == PAIRED], [5])
oob_clear()
E.disconnect(ka, 0x13)
E.settle()

# ---- BR/EDR Secure Connections Only -----------------------------------------------------------------------------
setup(b, 1, sc_only=1)
cb.ssp = False                                          # B's controller as an old one: PINs, combination keys
ka, kb = E.link()
reset()
pair(ka)
for _ in range(10):
    E.settle()
    for ad, conn in ((a, ka), (b, kb)):
        for i, (kind, _) in enumerate(asked[ad]):
            if kind == PIN and (ad, i, "pin") not in answered:
                answered.add((ad, i, "pin"))
                pin(conn, b"0000", 4)
check("SC only, a PIN pairing's key: not kept, the link ended",
      ([s for k, s in asked[b] if k == PAIRED], key_find(None, E.A_ADDR, 0),
       [c[1][2] for c in cb.cmd_log if c[0] == 0x0406]), ([5], 0, [5]))
cb.ssp = True
setup(b, 1)
E.settle()

# ---- LE privacy ----------------------------------------------------------------------------------------------------
check("privacy off: the public address", own_type(b), 0)
check("on: a new address set", (privacy(b, 1, 60), own_type(b), cb.random_addr is not None), (0, 1, True))
irk = bytes(C.string_at(C.addressof(C.c_uint8.in_dll(lib, "ubt_local_irk")), 16))
addr = cb.random_addr
prand, hsh = rev(addr[3:]), rev(addr[:3])
check("resolvable: top bits 01, the hash our IRK makes", (addr[5] >> 6, R.ah(rev(irk), prand)), (1, hsh))
heard = []


class Found(C.Structure):
    _fields_ = [("kind", C.c_uint8), ("addr_type", C.c_uint8), ("event_type", C.c_uint16), ("addr", C.c_uint8 * 6)]


GAP2 = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(
    lambda ad, kind, rec: heard.append((Found.from_address(rec).addr_type, bytes(Found.from_address(rec).addr)))
    if kind == 1 else None)
C.c_void_p.from_address(a + G[0]).value = C.cast(GAP2, C.c_void_p).value
advertise(b, 3, b"\x02\x01\x06", 3, None, 0)
scan(a, 0, 0)
E.settle()
check("advertising and scanning use it: A hears the random address", heard[:1], [(1, addr)])
scan_stop(a)
adv_stop(b)
old = cb.random_addr
E.now[0] += 61000
E.settle()
check("60 s later: a new address", (cb.random_addr != old, R.ah(rev(irk), rev(cb.random_addr[3:])) == rev(cb.random_addr[:3])),
      (True, True))
privacy(b, 0, 0)
check("off again", own_type(b), 0)
C.c_void_p.from_address(a + G[0]).value = C.cast(GAP, C.c_void_p).value

# ---- the resolving list -----------------------------------------------------------------------------------------------
la, lb = E.le_link()
reset()
pair(la)
run(((a, la), (b, lb)))
check("bonded with B (its IRK kept)", [s for k, s in asked[a] if k == PAIRED], [0])
check("A's resolving list made", resolving(a), 0)
check("an entry per bond with an IRK (both stacks share one store here); resolution on",
      (sorted(e[1:7] for e in ca.resolving), [(e[0], e[7:23], e[23:39]) for e in ca.resolving][:1], ca.resolution),
      (sorted([E.A_ADDR, E.B_ADDR]), [(0, irk, irk)], True))
E.disconnect(la, 0x13)
E.settle()
forget()

# ---- built-in services --------------------------------------------------------------------------------------------------
GL = list((C.c_uint32 * 8).in_dll(lib, "ubt_gatt_layout"))
db = C.create_string_buffer(GL[2])
C.c_void_p.from_address(b + G[4]).value = C.addressof(db)
fn("ubt_gatt_db_init", None, C.c_void_p)(db)
sc_h = fn("ubt_gatt_gap_gatt", C.c_uint32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32)(db, b"B", 1, 0)
dis = fn("ubt_gatt_dis", C.c_uint32, C.c_void_p, C.c_char_p, C.c_char_p, C.c_char_p)(db, b"Utkarsha Labs", b"UT-1", b"0.1")
bat = fn("ubt_gatt_battery", C.c_uint32, C.c_void_p, C.c_uint32)(db, 80)
check("Device Information after GAP and GATT, Battery after it", (sc_h, dis, bat), (8, 10, 19))
la, lb = E.le_link()
got = []
EVFN = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(
    lambda conn, kind, rec: got.append((kind, struct.unpack_from("<H", C.string_at(rec, 2))[0],
                                         C.string_at(C.c_uint64.from_address(rec + 40).value,
                                                     C.c_uint32.from_address(rec + 32).value)
                                         if C.c_uint64.from_address(rec + 40).value else b"")))
C.c_void_p.in_dll(lib, "ubt_gatt_fn").value = C.cast(EVFN, C.c_void_p).value
read = fn("ubt_gatt_read", C.c_int32, C.c_void_p, C.c_uint32)
subscribe = fn("ubt_gatt_subscribe", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
vals = []
for h in (12, 14, 16, bat):
    got.clear()
    read(la, h)
    E.settle()
    vals.append([g[2] for g in got if g[0] == 4])
check("manufacturer, model, software, battery level", vals, [[b"Utkarsha Labs"], [b"UT-1"], [b"0.1"], [b"\x50"]])
subscribe(la, bat + 1, 1)
E.settle()
got.clear()
check("battery level set: stored", fn("ubt_gatt_battery_set", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)(db, bat, 55), 0)
E.settle()
check("and notified to the subscriber", [(g[0], g[1], g[2]) for g in got], [(5, bat, b"\x37")])
subscribe(la, sc_h + 1, 2)
E.settle()
got.clear()
fn("ubt_gatt_changed", None, C.c_void_p, C.c_uint32, C.c_uint32, C.c_uint32)(db, sc_h, 10, 0xFFFF)
E.settle()
check("Service Changed indicated with the range", [(g[0], g[1], g[2]) for g in got],
      [(6, sc_h, struct.pack("<HH", 10, 0xFFFF))])

# ---- everything given back ------------------------------------------------------------------------------------------------
E.disconnect(la, 0x13)
E.settle()
E.remove(a)
E.remove(b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_extras: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

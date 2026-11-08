"""The LE Security Manager (sm/le.asm, sm/keys.asm): two of our stacks
pairing over the virtual radio in every model, with every value on the air
recomputed here from the specification's functions (smp_ref.py) so that a
mistake both stacks share still shows; then bonds, encryption from them,
keys, failures, the timeout and PDUs made by hand.

usage: python3 test_smp.py path/to/ubt.so
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
S = list((C.c_uint32 * 10).in_dll(lib, "ubt_smp_layout"))
CONFIRM, PASSKEY, SHOW, PAIRED, JUST_WORKS = 4, 5, 6, 8, 9
KEY_MITM, KEY_SC, KEY_LTK, KEY_OUR_LTK, KEY_IRK, KEY_CSRK = 1, 2, 8, 16, 32, 64
rev = lambda x: bytes(x[::-1])                  # noqa: E731


class Pairing(C.Structure):
    _fields_ = [("conn", C.c_uint64), ("value", C.c_uint32), ("status", C.c_uint32), ("addr", C.c_uint8 * 6),
                ("addr_type", C.c_uint8), ("le", C.c_uint8)]


class Key(C.Structure):
    _fields_ = [("used", C.c_uint8), ("peer_type", C.c_uint8), ("flags", C.c_uint8), ("key_size", C.c_uint8),
                ("link_type", C.c_uint8), ("pad", C.c_uint8), ("peer", C.c_uint8 * 6), ("ediv", C.c_uint16),
                ("our_ediv", C.c_uint16), ("rand", C.c_uint64), ("our_rand", C.c_uint64), ("ltk", C.c_uint8 * 16),
                ("our_ltk", C.c_uint8 * 16), ("irk", C.c_uint8 * 16), ("csrk", C.c_uint8 * 16),
                ("link_key", C.c_uint8 * 16), ("id_addr", C.c_uint8 * 6), ("id_type", C.c_uint8), ("pad2", C.c_uint8),
                ("sign_count", C.c_uint32), ("pad3", C.c_uint32)]


check("the records as the tests know them", (C.sizeof(Pairing), C.sizeof(Key)), (S[9], S[6]))

# ---- hooks: randomness, the user, the bond store ------------------------------------------------------
rng = random.Random(7)
randoms = []


def give_random(p, n):
    data = bytes(rng.getrandbits(8) for _ in range(n))
    C.memmove(p, data, n)
    randoms.append(data)
    return 0


RAND = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_uint32)(give_random)
C.c_void_p.in_dll(lib, "ubt_random_fn").value = C.cast(RAND, C.c_void_p).value
asked = {a: [], b: []}
saved = []


def on_gap(adapter, kind, rec):
    if kind in (CONFIRM, PASSKEY, SHOW, PAIRED, JUST_WORKS):
        p = Pairing.from_address(rec)
        asked[adapter].append((kind, p.value, p.status, p.conn))


GAP = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(on_gap)
KEYFN = C.CFUNCTYPE(None, C.c_void_p)(lambda e: saved.append(bytes(C.string_at(e, C.sizeof(Key)))))
C.c_void_p.in_dll(lib, "ubt_key_fn").value = C.cast(KEYFN, C.c_void_p).value
for ad in (a, b):
    C.c_void_p.from_address(ad + G[0]).value = C.cast(GAP, C.c_void_p).value
pair = E.fn("ubt_pair", C.c_int32, C.c_void_p)
confirm = E.fn("ubt_pair_confirm", None, C.c_void_p, C.c_uint32)
passkey = E.fn("ubt_pair_passkey", None, C.c_void_p, C.c_uint32)
key_find = E.fn("ubt_key_find", C.c_uint64, C.c_void_p, C.c_char_p, C.c_uint32)
key_forget = E.fn("ubt_key_forget", None, C.c_void_p, C.c_char_p, C.c_uint32)
key_resolve = E.fn("ubt_key_resolve", C.c_uint64, C.c_char_p)


def setup(adapter, io, bond=1, sc_only=0, legacy=0):
    C.c_uint8.from_address(adapter + G[1]).value = io
    C.c_uint8.from_address(adapter + G[2]).value = bond
    C.c_uint8.from_address(adapter + G[3]).value = sc_only
    C.c_uint8.from_address(adapter + G[15]).value = legacy


def smp_pdus(ctrl, start):
    return [f[4:] for f in E.frames(ctrl, start) if struct.unpack_from("<H", f, 2)[0] == 6]


def by_code(pdus, code):
    return [p[1:] for p in pdus if p[0] == code]


def run(answer=None, rounds=40):
    """Settle; the users answer what they were asked; again, until quiet."""
    answer = answer or {}
    for _ in range(rounds):
        E.settle()
        moved = False
        for ad, conn in ((a, la), (b, lb)):
            for ev in asked[ad]:
                kind, value = ev[0], ev[1]
                if ev in answered:
                    continue
                if kind in (CONFIRM, JUST_WORKS):
                    confirm(conn, answer.get((ad, kind), 1))
                elif kind == PASSKEY and (ad, PASSKEY) in answer:
                    passkey(conn, answer[(ad, PASSKEY)](value))
                else:
                    continue
                answered.append(ev)
                moved = True
        if not moved:
            E.settle()
            return


answered = []


def paired(ad):
    return [ev[2] for ev in asked[ad] if ev[0] == PAIRED]


def key_of(addr, typ=0):
    p = key_find(None, addr, typ)
    return Key.from_address(p) if p else None


def link():
    global la, lb, LA, LB
    la, lb = E.le_link()
    LA, LB = Conn.from_address(la), Conn.from_address(lb)


def unlink():
    E.disconnect(la, 0x13)
    E.settle()


def find_priv(pub_onair):
    """Which 32 random bytes made this public key (the side's private key)."""
    want = (int.from_bytes(pub_onair[:32], "little"), int.from_bytes(pub_onair[32:], "little"))
    for r in randoms:
        if len(r) == 32 and 0 < int.from_bytes(r, "big") < R.N and R.mul(int.from_bytes(r, "big")) == want:
            return int.from_bytes(r, "big")
    return None


def reset():
    for ad in (a, b):
        asked[ad].clear()
    randoms.clear()
    saved.clear()


A7 = bytes([0]) + rev(E.A_ADDR)
B7 = bytes([0]) + rev(E.B_ADDR)


def sc_values(pa, pb, passkey_value=None):
    """Everything the SC exchange put on the air, recomputed from it."""
    req, rsp = by_code(pa, 1)[0], by_code(pb, 2)[0]
    pka, pkb = by_code(pa, 0x0C)[0], by_code(pb, 0x0C)[0]
    na, nb = by_code(pa, 4)[-1], by_code(pb, 4)[-1]
    priv = find_priv(pka)
    x = R.mul(priv, (int.from_bytes(pkb[:32], "little"), int.from_bytes(pkb[32:], "little")))[0]
    dh = x.to_bytes(32, "big")
    mac, ltk = R.f5(dh, rev(na), rev(nb), A7, B7)
    r = bytes(12) + passkey_value.to_bytes(4, "big") if passkey_value is not None else bytes(16)
    ea = rev(R.f6(mac, rev(na), rev(nb), r, bytes([req[2], req[1], req[0]]), A7, B7))
    eb = rev(R.f6(mac, rev(nb), rev(na), r, bytes([rsp[2], rsp[1], rsp[0]]), B7, A7))
    return dict(req=req, rsp=rsp, pka=pka, pkb=pkb, na=na, nb=nb, ltk=rev(ltk), ea=ea, eb=eb, priv=priv)


# ---- Secure Connections, Just Works ------------------------------------------------------------------------
link()
setup(a, 3)
setup(b, 3)
reset()
ma, mb = len(ca.sent), len(cb.sent)
check("A pairs", pair(la), 0)
run()
pa, pb = smp_pdus(ca, ma), smp_pdus(cb, mb)
check("Pairing Request: no IO, no OOB, bonding and SC, 16 bytes, every key",
      by_code(pa, 1), [bytes([3, 0, 0x09, 16, 7, 7])])
check("Pairing Response the same", by_code(pb, 2), [bytes([3, 0, 0x09, 16, 7, 7])])
check("the order on the air", ([p[0] for p in pa], [p[0] for p in pb]),
      ([1, 0x0C, 4, 0x0D, 8, 9, 0x0A], [2, 0x0C, 3, 4, 0x0D, 8, 9, 0x0A]))
V = sc_values(pa, pb)
cb_ = by_code(pb, 3)[0]
check("Cb = f4(PKbx, PKax, Nb, 0)", cb_, rev(R.f4(rev(V["pkb"][:32]), rev(V["pka"][:32]), rev(V["nb"]), 0)))
check("Ea and Eb = f6 of the MacKey f5 made", (by_code(pa, 0x0D), by_code(pb, 0x0D)), ([V["ea"]], [V["eb"]]))
check("the link encrypted with f5's LTK", (cb.keys_used[-1:], [c[1][12:] for c in ca.cmd_log if c[0] == 0x2019][-1:]),
      ([V["ltk"]], [V["ltk"]]))
check("both asked whether Just Works is fine, both paired",
      ([e[0] for e in asked[a]], [e[0] for e in asked[b]], paired(a), paired(b)),
      ([JUST_WORKS, PAIRED], [JUST_WORKS, PAIRED], [0], [0]))
check("encrypted, not authenticated", (LA.sec, LB.sec, LA.key_size), (1, 1, 16))
ka, kb = key_of(E.B_ADDR), key_of(E.A_ADDR)
check("bonds on both sides: SC, the same LTK, IRK, identity address, CSRK",
      (ka.flags, kb.flags, bytes(ka.ltk), bytes(kb.our_ltk), bytes(ka.id_addr), bytes(kb.id_addr)),
      (KEY_SC | KEY_LTK | KEY_OUR_LTK | KEY_IRK | KEY_CSRK, KEY_SC | KEY_LTK | KEY_OUR_LTK | KEY_IRK | KEY_CSRK,
       V["ltk"], V["ltk"], E.B_ADDR, E.A_ADDR))
check("the store's hook told of each", len(saved), 2)
check("the IRK and CSRK sent are ours", (bytes(by_code(pb, 8)[0]), bytes(ka.irk)), (bytes(C.string_at(
    C.addressof(C.c_uint8.in_dll(lib, "ubt_local_irk")), 16)),) * 2)

# ---- a bond's key next time --------------------------------------------------------------------------------
unlink()
link()
reset()
ma = len(ca.sent)
check("A secures the new link", pair(la), 0)
run()
check("no pairing: the bond's LTK, EDIV and Rand 0", (smp_pdus(ca, ma), cb.keys_used[-1], paired(a)),
      ([], V["ltk"], [0]))
check("encrypted as the bond was", LA.sec, 1)

# ---- numeric comparison -----------------------------------------------------------------------------------------
key_forget(None, E.B_ADDR, 0)
key_forget(None, E.A_ADDR, 0)
check("forgotten: the hook told with used = 0", [s[0] for s in saved[-2:]], [0, 0])
unlink()
link()
setup(a, 1)
setup(b, 1)
reset()
ma, mb = len(ca.sent), len(cb.sent)
pair(la)
run()
V = sc_values(smp_pdus(ca, ma), smp_pdus(cb, mb))
number = R.g2(rev(V["pka"][:32]), rev(V["pkb"][:32]), rev(V["na"]), rev(V["nb"])) % 1000000
check("both shown g2's six digits", ([e[1] for e in asked[a] if e[0] == CONFIRM], [e[1] for e in asked[b] if e[0] == CONFIRM]),
      ([number], [number]))
check("both said yes: paired, authenticated with SC", (paired(a), paired(b), LA.sec, LB.sec), ([0], [0], 3, 3))
check("the bond says MITM", key_of(E.B_ADDR).flags & (KEY_MITM | KEY_SC), KEY_MITM | KEY_SC)
unlink()
link()
reset()
pair(la)
run()
check("next time: authenticated from the bond", (LA.sec, paired(a)), (3, [0]))
key_forget(None, E.B_ADDR, 0)
key_forget(None, E.A_ADDR, 0)
unlink()
link()
reset()
mb = len(cb.sent)
pair(la)
run({(b, CONFIRM): 0})
check("B says the numbers differ: Numeric Comparison Failed both ways", (paired(a), paired(b), by_code(smp_pdus(cb, mb), 5)),
      ([0x0C], [0x0C], [b"\x0c"]))
check("not encrypted, no bond", (LA.sec, key_of(E.B_ADDR)), (0, None))

# ---- passkey entry (SC, 20 rounds) ---------------------------------------------------------------------------------
unlink()
link()
setup(a, 2)                                             # keyboard only: types
setup(b, 0)                                             # display only: shows
reset()
ma, mb = len(ca.sent), len(cb.sent)
pair(la)
run(rounds=1)
shown = [e[1] for e in asked[b] if e[0] == SHOW]
check("B shows a passkey, A is asked for it", (len(shown), shown[0] < 1000000, [e[0] for e in asked[a]]), (1, True, [PASSKEY]))
run({(a, PASSKEY): lambda v: shown[0]})
pa, pb = smp_pdus(ca, ma), smp_pdus(cb, mb)
check("twenty rounds of confirm and random each way", [len(by_code(p, c)) for p in (pa, pb) for c in (3, 4)], [20] * 4)
bad = []
pka, pkb = by_code(pa, 0x0C)[0], by_code(pb, 0x0C)[0]
for i, (cai, cbi, nai, nbi) in enumerate(zip(by_code(pa, 3), by_code(pb, 3), by_code(pa, 4), by_code(pb, 4))):
    z = 0x80 | (shown[0] >> i & 1)
    if cai != rev(R.f4(rev(pka[:32]), rev(pkb[:32]), rev(nai), z)) or \
            cbi != rev(R.f4(rev(pkb[:32]), rev(pka[:32]), rev(nbi), z)):
        bad.append(i)
check("each round's confirms carry that bit of the passkey", bad, [])
V = sc_values(pa, pb, shown[0])
check("the checks use the passkey as r", (by_code(pa, 0x0D), by_code(pb, 0x0D)), ([V["ea"]], [V["eb"]]))
check("paired, authenticated", (paired(a), paired(b), LA.sec), ([0], [0], 3))
key_forget(None, E.B_ADDR, 0)
key_forget(None, E.A_ADDR, 0)
unlink()
link()
reset()
pair(la)
run(rounds=1)
shown = [e[1] for e in asked[b] if e[0] == SHOW]
wrong = shown[0] ^ 1 << 3                               # bit 3 differs
run({(a, PASSKEY): lambda v: wrong})
check("a wrong passkey: Confirm Value Failed in its round", (paired(a), paired(b)), ([0x04], [0x04]))
unlink()
link()
reset()
pair(la)
run({(a, PASSKEY): lambda v: 1000000})
check("cancelled: Passkey Entry Failed", (paired(a), paired(b)), ([0x01], [0x01]))

# ---- LE legacy pairing ------------------------------------------------------------------------------------------------
unlink()
link()
setup(a, 3, legacy=1)
setup(b, 3)
reset()
ma, mb = len(ca.sent), len(cb.sent)
pair(la)
run()
pa, pb = smp_pdus(ca, ma), smp_pdus(cb, mb)
check("legacy, Just Works: no public keys, keys sent", ([p[0] for p in pa], [p[0] for p in pb]),
      ([1, 3, 4, 6, 7, 8, 9, 0x0A], [2, 3, 4, 6, 7, 8, 9, 0x0A]))
req, rsp = bytes([1]) + by_code(pa, 1)[0], bytes([2]) + by_code(pb, 2)[0]
mc, sc_, mr, sr = by_code(pa, 3)[0], by_code(pb, 3)[0], by_code(pa, 4)[0], by_code(pb, 4)[0]
tk = bytes(16)
c1 = lambda r: rev(R.c1(tk, rev(r), rev(req), rev(rsp), 0, 0, rev(E.A_ADDR), rev(E.B_ADDR)))   # noqa: E731
check("Mconfirm and Sconfirm = c1(TK 0, ...)", (mc, sc_), (c1(mr), c1(sr)))
stk = rev(R.s1(tk, rev(sr), rev(mr)))
check("the STK = s1(TK, Srand, Mrand) encrypts", cb.keys_used[-1], stk)
ka, kb = key_of(E.B_ADDR), key_of(E.A_ADDR)
check("bonds: B's LTK with its EDIV and Rand kept by both, A's too",
      (bytes(ka.ltk), ka.ediv, ka.rand, bytes(kb.our_ltk), kb.our_ediv, kb.our_rand, bytes(kb.ltk), bytes(ka.our_ltk)),
      (bytes(kb.our_ltk), kb.our_ediv, kb.our_rand, by_code(pb, 6)[0], *struct.unpack("<HQ", by_code(pb, 7)[0]),
       by_code(pa, 6)[0], by_code(pa, 6)[0]))
check("legacy, not SC, not MITM", (ka.flags & (KEY_SC | KEY_MITM), paired(a), paired(b), LA.sec), (0, [0], [0], 1))
unlink()
link()
reset()
pair(la)
run()
check("next time: B's LTK, with its EDIV and Rand", ([c[1][2:12] for c in ca.cmd_log if c[0] == 0x2019][-1],
                                                        cb.keys_used[-1], paired(a)),
      (struct.pack("<QH", ka.rand, ka.ediv), bytes(ka.ltk), [0]))
key_forget(None, E.B_ADDR, 0)
key_forget(None, E.A_ADDR, 0)
unlink()
link()
setup(a, 4, legacy=1)                                   # keyboard and display, both: A shows
setup(b, 4)
reset()
ma, mb = len(ca.sent), len(cb.sent)
pair(la)
run(rounds=1)
shown = [e[1] for e in asked[a] if e[0] == SHOW]
check("legacy passkey: the initiator shows, the responder types", ([e[0] for e in asked[a]], [e[0] for e in asked[b]]),
      ([SHOW], [PASSKEY]))
run({(b, PASSKEY): lambda v: shown[0]})
pa, pb = smp_pdus(ca, ma), smp_pdus(cb, mb)
tk = bytes(12) + shown[0].to_bytes(4, "big")
req, rsp = bytes([1]) + by_code(pa, 1)[0], bytes([2]) + by_code(pb, 2)[0]
check("the TK is the passkey", by_code(pa, 3)[0], rev(R.c1(tk, rev(by_code(pa, 4)[0]), rev(req), rev(rsp), 0, 0,
                                                             rev(E.A_ADDR), rev(E.B_ADDR))))
check("paired, authenticated (legacy)", (paired(a), paired(b), LA.sec, key_of(E.B_ADDR).flags & KEY_MITM),
      ([0], [0], 2, KEY_MITM))
key_forget(None, E.B_ADDR, 0)
key_forget(None, E.A_ADDR, 0)

# ---- policy, the peripheral asking, refusals ---------------------------------------------------------------------------
unlink()
link()
setup(a, 3, legacy=1)
setup(b, 3, sc_only=1)
reset()
mb = len(cb.sent)
pair(la)
run()
check("B takes Secure Connections only: A's legacy refused (Authentication Requirements)",
      (by_code(smp_pdus(cb, mb), 5), paired(a), paired(b)), ([b"\x03"], [3], [3]))
setup(a, 3)
setup(b, 3)
reset()
ma, mb = len(ca.sent), len(cb.sent)
check("B, the peripheral, asks", pair(lb), 0)
run()
check("a Security Request, then A pairs", (smp_pdus(cb, mb)[0], smp_pdus(ca, ma)[0][0], paired(a), paired(b)),
      (bytes([0x0B, 0x09]), 1, [0], [0]))
key_forget(None, E.B_ADDR, 0)
key_forget(None, E.A_ADDR, 0)
setup(b, 3, bond=0)
unlink()
link()
reset()
saved.clear()
mb = len(cb.sent)
pair(la)
run()
check("B does not bond: paired, no keys sent, nothing kept",
      (by_code(smp_pdus(cb, mb), 2), paired(a), paired(b), key_of(E.B_ADDR), saved),
      ([bytes([3, 0, 0x08, 16, 0, 0])], [0], [0], None, []))
setup(b, 3)

# ---- by hand, to B ------------------------------------------------------------------------------------------------------
unlink()
link()
ca.deaf = True


def to_b(pdu):
    mark = len(cb.sent)
    E.inject(cb, LB.handle, struct.pack("<HH", len(pdu), 6) + pdu)
    return smp_pdus(cb, mark)


check("an unknown code: Command Not Supported", to_b(b"\x20\x00"), [b"\x05\x07"])
check("a Pairing Request of the wrong length: Invalid Parameters", to_b(b"\x01\x03\x00"), [b"\x05\x0a"])
check("a key size of 6: Encryption Key Size", to_b(bytes([1, 3, 0, 9, 6, 7, 7])), [b"\x05\x06"])
reset()
check("a Pairing Random out of turn, while pairing: Unspecified Reason",
      [p[0] for p in to_b(bytes([1, 3, 0, 9, 16, 7, 7]))] + [p for p in to_b(bytes([4]) + bytes(16))],
      [2, b"\x05\x08"])
check("and B's user told", paired(b), [8])
mark = len(cb.sent)
E.radio.inject_event(cb, 0x3E, bytes([0x05]) + struct.pack("<H", LB.handle) + bytes(8) + b"\x00\x00")
E.settle()
check("an LTK asked for with no pairing and no bond: refused", [c[0] for c in cb.cmd_log[-1:]], [0x201B])
ca.deaf = False

# ---- the 30-second timeout ------------------------------------------------------------------------------------------------
reset()
cb.deaf = True
pair(la)
E.settle()
E.now[0] += 30001
E.settle()
check("no answer in 30 s: failed (timeout)", paired(a), [0x100])
cb.deaf = False
ma = len(ca.sent)
E.inject(ca, LA.handle, struct.pack("<HH", 2, 6) + b"\x0b\x09")
check("and no more SMP on that link", smp_pdus(ca, ma), [])

# ---- resolvable private addresses ------------------------------------------------------------------------------------------
unlink()
link()
setup(a, 3)
setup(b, 3)
reset()
pair(la)
run()
key_forget(None, E.A_ADDR, 0)                           # (both stacks here share one IRK)
irk = bytes(key_of(E.B_ADDR).irk)                       # B's, on-air order
prand = bytes([0x12, 0x34, 0x56 | 0x40])[::-1]          # most significant first: 0x56|0x40, 0x34, 0x12
h = R.ah(rev(irk), prand)
rpa = rev(h) + rev(prand)                               # least significant first: hash, then prand
check("an address B's IRK made: resolved to B's bond", key_resolve(rpa), key_find(None, E.B_ADDR, 0))
check("and found by it as a random address", key_find(None, rpa, 1), key_find(None, E.B_ADDR, 0))
check("another: not", key_resolve(bytes([1, 2, 3, 4, 5, 0x41])), 0)

# ---- everything given back ----------------------------------------------------------------------------------------------------
unlink()
E.remove(a)
E.remove(b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_smp: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

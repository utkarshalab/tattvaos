"""BR/EDR pairing (sm/br.asm): Secure Simple Pairing and legacy PINs
between two of our stacks, the controllers' part played by the virtual
radio; bonds, authentication from them, encryption, refusals.

usage: python3 test_brpair.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env, Conn  # noqa: E402

E = Env(sys.argv[1])
check, a, b, ca, cb, lib = E.check, E.a, E.b, E.ca, E.cb, E.lib
G = list((C.c_uint32 * 16).in_dll(lib, "ubt_gap_layout"))
CONFIRM, PASSKEY, SHOW, PIN, PAIRED, JUST_WORKS = 4, 5, 6, 7, 8, 9
KEY_MITM, KEY_SC, KEY_LINK = 1, 2, 4


class Pairing(C.Structure):
    _fields_ = [("conn", C.c_uint64), ("value", C.c_uint32), ("status", C.c_uint32), ("addr", C.c_uint8 * 6),
                ("addr_type", C.c_uint8), ("le", C.c_uint8)]


asked = {a: [], b: []}
saved = []


def on_gap(adapter, kind, rec):
    if kind in (CONFIRM, PASSKEY, SHOW, PIN, PAIRED, JUST_WORKS):
        p = Pairing.from_address(rec)
        asked[adapter].append((kind, p.value, p.status, p.le))


GAP = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(on_gap)
KEYFN = C.CFUNCTYPE(None, C.c_void_p)(lambda e: saved.append(C.string_at(e, 8)))
C.c_void_p.in_dll(lib, "ubt_key_fn").value = C.cast(KEYFN, C.c_void_p).value
for ad in (a, b):
    C.c_void_p.from_address(ad + G[0]).value = C.cast(GAP, C.c_void_p).value
fn = E.fn
pair = fn("ubt_pair", C.c_int32, C.c_void_p)
confirm = fn("ubt_pair_confirm", None, C.c_void_p, C.c_uint32)
passkey = fn("ubt_pair_passkey", None, C.c_void_p, C.c_uint32)
pin = fn("ubt_pair_pin", None, C.c_void_p, C.c_char_p, C.c_uint32)
enable = fn("ubt_br_enable", None, C.c_void_p)
key_find = fn("ubt_key_find", C.c_uint64, C.c_void_p, C.c_char_p, C.c_uint32)
key_forget = fn("ubt_key_forget", None, C.c_void_p, C.c_char_p, C.c_uint32)
enable(a)
enable(b)
E.settle()
check("Simple Pairing turned on in both controllers", (ca.ssp, cb.ssp), (True, True))


def setup(ad, io, bond=1):
    C.c_uint8.from_address(ad + G[1]).value = io
    C.c_uint8.from_address(ad + G[2]).value = bond


def kinds(ad):
    return [e[0] for e in asked[ad]]


def paired(ad):
    return [e[2] for e in asked[ad] if e[0] == PAIRED]


def run(answers):
    """Settle; each side answers what it is asked, once; until quiet."""
    done = set()
    for _ in range(20):
        E.settle()
        moved = False
        for ad, conn in ((a, ka), (b, kb)):
            for i, ev in enumerate(asked[ad]):
                if (ad, i) in done or ev[0] not in answers.get(ad, {}):
                    continue
                done.add((ad, i))
                ans = answers[ad][ev[0]]
                if ev[0] in (CONFIRM, JUST_WORKS):
                    confirm(conn, ans)
                elif ev[0] == PASSKEY:
                    passkey(conn, ans)
                elif ev[0] == PIN:
                    pin(conn, ans, len(ans))
                moved = True
        if not moved:
            return


class Key(C.Structure):
    _fields_ = [("used", C.c_uint8), ("peer_type", C.c_uint8), ("flags", C.c_uint8), ("key_size", C.c_uint8),
                ("link_type", C.c_uint8), ("pad", C.c_uint8), ("peer", C.c_uint8 * 6), ("ediv", C.c_uint16),
                ("our_ediv", C.c_uint16), ("rand", C.c_uint64), ("our_rand", C.c_uint64), ("ltk", C.c_uint8 * 16),
                ("our_ltk", C.c_uint8 * 16), ("irk", C.c_uint8 * 16), ("csrk", C.c_uint8 * 16),
                ("link_key", C.c_uint8 * 16)]


def bond(addr):
    p = key_find(None, addr, 0)
    return Key.from_address(p) if p else None


def fresh():
    global ka, kb, KA, KB
    for ad in (a, b):
        asked[ad].clear()
    saved.clear()
    ka, kb = E.link()
    KA, KB = Conn.from_address(ka), Conn.from_address(kb)


def gone():
    E.disconnect(ka, 0x13)
    E.settle()


def forget():
    key_forget(None, E.A_ADDR, 0)
    key_forget(None, E.B_ADDR, 0)


# ---- numeric comparison --------------------------------------------------------------------------------
setup(a, 1)
setup(b, 1)
fresh()
mark = len(ca.cmd_log)
check("A pairs", pair(ka), 0)
run({a: {CONFIRM: 1}, b: {CONFIRM: 1}})
check("both shown the number, both paired", (asked[a], asked[b]),
      ([(CONFIRM, 123456, 0, 0), (PAIRED, 0, 0, 0)], [(CONFIRM, 123456, 0, 0), (PAIRED, 0, 0, 0)]))
cmds = [c[0] for c in ca.cmd_log[mark:]]
check("A: authenticate, no key, IO capability, confirmed, then encrypt",
      [c for c in cmds if c in (0x0411, 0x040C, 0x042B, 0x042C, 0x0413)], [0x0411, 0x040C, 0x042B, 0x042C, 0x0413])
io = [c[1] for c in ca.cmd_log[mark:] if c[0] == 0x042B][0]
check("A's IO capability: display yes/no, no OOB, general bonding with MITM", io[6:], bytes([1, 0, 5]))
check("encrypted, authenticated with Secure Connections", (KA.sec, KB.sec), (3, 3))
ba, bb = bond(E.B_ADDR), bond(E.A_ADDR)
check("both keep the link key, P-256 authenticated",
      (ba.flags, bb.flags, ba.link_type, bytes(ba.link_key), bytes(bb.link_key)),
      (KEY_LINK | KEY_MITM | KEY_SC, KEY_LINK | KEY_MITM | KEY_SC, 8, ca.pair_key, ca.pair_key))
check("the store's hook told", len(saved), 2)

# ---- the bond next time -----------------------------------------------------------------------------------
gone()
fresh()
mark = len(ca.cmd_log)
pair(ka)
run({})
check("next time: the link key from the bond, nothing asked", (kinds(a), kinds(b), paired(a)), ([PAIRED], [], [0]))
check("A answered with its key", [c[1][6:] for c in ca.cmd_log[mark:] if c[0] == 0x040B], [ca.pair_key])
check("encrypted, authenticated", (KA.sec, KB.sec), (3, 3))
key_forget(None, E.A_ADDR, 0)                           # B loses its key
gone()
fresh()
pair(ka)
run({})
check("the peer lost its key: Authentication Complete 'key missing'", paired(a), [0x06])
forget()

# ---- refused, Just Works, passkey ---------------------------------------------------------------------------
gone()
fresh()
pair(ka)
run({a: {CONFIRM: 1}, b: {CONFIRM: 0}})
check("B says the numbers differ: both told it failed", (paired(a), paired(b), bond(E.B_ADDR)), ([5], [5], None))
setup(a, 3)
setup(b, 3)
gone()
fresh()
pair(ka)
run({a: {JUST_WORKS: 1}, b: {JUST_WORKS: 1}})
check("no IO on either: Just Works asked, unauthenticated", (kinds(a), kinds(b), KA.sec, bond(E.B_ADDR).link_type),
      ([JUST_WORKS, PAIRED], [JUST_WORKS, PAIRED], 1, 7))
forget()
setup(a, 2)                                             # A types
setup(b, 0)                                             # B shows
gone()
fresh()
pair(ka)
run({a: {PASSKEY: 123456}})
check("passkey: A asked to type, B shows it", ([e[:2] for e in asked[a]], [e[:2] for e in asked[b]]),
      ([(PASSKEY, 0), (PAIRED, 0)], [(SHOW, 123456), (PAIRED, 0)]))
check("authenticated", (KA.sec, paired(b)), (3, [0]))
forget()
gone()
fresh()
pair(ka)
run({a: {PASSKEY: 654321}})
check("a wrong passkey: failed", (paired(a), paired(b)), ([5], [5]))
gone()
fresh()
pair(ka)
run({a: {PASSKEY: 1000000}})
check("cancelled: failed", paired(a), [5])

# ---- not bonding --------------------------------------------------------------------------------------------
setup(a, 1)
setup(b, 1, bond=0)
gone()
fresh()
pair(ka)
run({a: {CONFIRM: 1}, b: {CONFIRM: 1}})
check("B does not bond: paired, nobody keeps the key", (paired(a), paired(b), bond(E.B_ADDR), bond(E.A_ADDR), saved),
      ([0], [0], None, None, []))
setup(b, 1)

# ---- legacy PIN pairing ----------------------------------------------------------------------------------------
cb.ssp = False                                          # B's controller as an old one
gone()
fresh()
pair(ka)
run({a: {PIN: b"0000"}, b: {PIN: b"0000"}})
check("legacy: both asked for a PIN, the same: paired", (kinds(a), paired(a), paired(b)), ([PIN, PAIRED], [0], [0]))
pins = [c[1] for c in ca.cmd_log if c[0] == 0x040D][-1]
check("the PIN Code Reply: length, then 16 bytes", pins[6:], bytes([4]) + b"0000" + bytes(12))
check("a combination key, not authenticated", (bond(E.B_ADDR).link_type, KA.sec), (0, 1))
forget()
gone()
fresh()
pair(ka)
run({a: {PIN: b"1234"}, b: {PIN: b"9999"}})
check("different PINs: A told it failed (a legacy responder hears nothing)", (paired(a), paired(b)), ([5], []))
C.c_void_p.from_address(b + G[0]).value = None          # B without a user to ask
gone()
fresh()
mark = len(cb.cmd_log)
pair(ka)
run({a: {PIN: b"0000"}})
check("nobody to ask for a PIN: refused", ([c[0] for c in cb.cmd_log[mark:] if c[0] in (0x040D, 0x040E)], paired(a)),
      ([0x040E], [5]))
C.c_void_p.from_address(b + G[0]).value = C.cast(GAP, C.c_void_p).value
cb.ssp = True

# ---- by hand ------------------------------------------------------------------------------------------------------
mark = len(cb.cmd_log)
E.radio.inject_event(cb, 0x31, bytes([0x77] * 6))      # IO capability for a peer with no link
E.settle()
check("an IO Capability Request for nobody we know: refused", [c[0] for c in cb.cmd_log[mark:]], [0x0434])

# ---- everything given back ----------------------------------------------------------------------------------------
forget()
gone()
E.remove(a)
E.remove(b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_brpair: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

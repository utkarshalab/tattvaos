"""ATT and GATT (gatt/db.asm, att/server.asm, att/client.asm): our client
against our server over an LE link on the virtual radio, every procedure,
permissions against the link's security, notifications and indications,
signed writes checked here independently, and requests made by hand.

usage: python3 test_gatt.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smp_ref as R  # noqa: E402
from l2cap_env import Env, Conn  # noqa: E402

E = Env(sys.argv[1])
check, a, b, ca, cb, lib = E.check, E.a, E.b, E.ca, E.cb, E.lib
G = list((C.c_uint32 * 16).in_dll(lib, "ubt_gap_layout"))
GL = list((C.c_uint32 * 8).in_dll(lib, "ubt_gatt_layout"))
AL = list((C.c_uint32 * 8).in_dll(lib, "ubt_att_layout"))
SERVICE, CHAR, DESC, VALUE, NOTIFY, INDICATE, DONE = range(1, 8)
P_MTU, P_SERVICES, P_UUID, P_CHARS, P_DESCS, P_READ, P_MULT, P_WRITE, P_LONG = range(1, 10)
READ, WRITE_NR, WRITE, NOTIFY_P, INDICATE_P, SIGNED = 0x02, 0x04, 0x08, 0x10, 0x20, 0x40
PR, PW, PR_ENC, PW_ENC, PR_AUTH, PW_AUTH = 1, 2, 4, 8, 16, 32
rev = lambda x: bytes(x[::-1])  # noqa: E731


class Def(C.Structure):
    _fields_ = [("uuid", C.c_uint8 * 16), ("uuid_len", C.c_uint8), ("props", C.c_uint8), ("perm", C.c_uint16),
                ("len", C.c_uint16), ("max", C.c_uint16), ("value", C.c_void_p), ("read_fn", C.c_void_p),
                ("write_fn", C.c_void_p), ("user", C.c_uint64)]


class Ev(C.Structure):
    _fields_ = [("handle", C.c_uint16), ("end", C.c_uint16), ("value_handle", C.c_uint16), ("props", C.c_uint8),
                ("uuid_len", C.c_uint8), ("uuid", C.c_uint8 * 16), ("status", C.c_uint32), ("proc", C.c_uint32),
                ("len", C.c_uint32), ("pad", C.c_uint32), ("data", C.c_uint64)]


check("the records as the tests know them", (C.sizeof(Def), C.sizeof(Ev)),
      (GL[1], list((C.c_uint32 * 4).in_dll(lib, "ubt_gatt_ev_layout"))[0]))
fn = E.fn
db_init = fn("ubt_gatt_db_init", None, C.c_void_p)
service = fn("ubt_gatt_service", C.c_uint32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32)
char_ = fn("ubt_gatt_char", C.c_uint32, C.c_void_p, C.c_void_p)
desc = fn("ubt_gatt_desc", C.c_uint32, C.c_void_p, C.c_void_p)
gap_gatt = fn("ubt_gatt_gap_gatt", C.c_uint32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32)
gset = fn("ubt_gatt_set", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
gattr = fn("ubt_gatt_attr", C.c_uint64, C.c_void_p, C.c_uint32)
mtu = fn("ubt_gatt_mtu", C.c_int32, C.c_void_p)
services = fn("ubt_gatt_services", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
chars = fn("ubt_gatt_chars", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
descs = fn("ubt_gatt_descs", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
read = fn("ubt_gatt_read", C.c_int32, C.c_void_p, C.c_uint32)
read_mult = fn("ubt_gatt_read_multiple", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
write = fn("ubt_gatt_write", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
write_cmd = fn("ubt_gatt_write_cmd", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
write_signed = fn("ubt_gatt_write_signed", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
subscribe = fn("ubt_gatt_subscribe", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
notify = fn("ubt_gatt_notify", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
indicate = fn("ubt_gatt_indicate", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32)
pair = fn("ubt_pair", C.c_int32, C.c_void_p)

# ---- B's database ---------------------------------------------------------------------------------------
dbb = C.create_string_buffer(GL[2])
C.c_void_p.from_address(b + G[4]).value = C.addressof(dbb)
db_init(dbb)
check("GAP and GATT services: Service Changed at 8", gap_gatt(dbb, b"Utk B", 5, 0x03C1), 8)
U128 = bytes(range(0x10, 0x20))
C128 = bytes(range(0xA0, 0xB0))
keep = []


def d(uuid, props, perm, value=b"", max_=None, read_fn=None, write_fn=None):
    x = Def()
    u = struct.pack("<H", uuid) if isinstance(uuid, int) else uuid
    C.memmove(x.uuid, u, len(u))
    x.uuid_len, x.props, x.perm = len(u), props, perm
    buf = C.create_string_buffer(value, max(len(value), 1))
    keep.append(buf)
    x.len, x.max, x.value = len(value), max_ if max_ is not None else len(value), C.addressof(buf)
    x.read_fn, x.write_fn = read_fn, write_fn
    return x


svc_bat = service(dbb, struct.pack("<H", 0x180F), 2, 1)
lvl = char_(dbb, C.byref(d(0x2A19, READ | NOTIFY_P, PR, b"\x4d")))
LONG = bytes((i * 5) & 0xFF for i in range(300))
svc_c = service(dbb, U128, 16, 1)
cv = char_(dbb, C.byref(d(C128, READ | WRITE | WRITE_NR | INDICATE_P | SIGNED, PR | PW, LONG, 512)))
udesc = desc(dbb, C.byref(d(0x2901, 0, PR, b"Custom")))
svc_p = service(dbb, struct.pack("<H", 0xFFF0), 2, 1)
enc = char_(dbb, C.byref(d(0xFFF1, READ, PR | PR_ENC, b"secret")))
auth = char_(dbb, C.byref(d(0xFFF2, READ | WRITE, PR | PW | PW_AUTH, b"\x00", 8)))
seen_writes = []


def cb_read(conn, attr, offset, out, room):
    v = b"from Python"[offset:][:room]
    C.memmove(out, v, len(v))
    return len(v)


def cb_write(conn, attr, offset, data, n):
    seen_writes.append(C.string_at(data, n))
    return -0x80 if C.string_at(data, n) == b"no" else 0


RD = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32)(cb_read)
WR = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_void_p, C.c_uint32, C.c_void_p, C.c_uint32)(cb_write)
cbh = char_(dbb, C.byref(d(0xFFF3, READ | WRITE, PR | PW, read_fn=C.cast(RD, C.c_void_p).value,
                           write_fn=C.cast(WR, C.c_void_p).value)))
check("the handles as laid out", (svc_bat, lvl, svc_c, cv, udesc, svc_p, enc, auth, cbh),
      (10, 12, 14, 16, 18, 19, 21, 23, 25))
LAST = 25

# ---- the client's ears ----------------------------------------------------------------------------------
heard = []


def on_gatt(conn, kind, rec):
    e = Ev.from_address(rec)
    data = C.string_at(e.data, e.len) if e.data else b""
    if kind == SERVICE:
        heard.append(("svc", e.handle, e.end, bytes(e.uuid[:e.uuid_len])))
    elif kind == CHAR:
        heard.append(("chr", e.handle, e.props, e.value_handle, bytes(e.uuid[:e.uuid_len])))
    elif kind == DESC:
        heard.append(("dsc", e.handle, bytes(e.uuid[:e.uuid_len])))
    elif kind in (VALUE, NOTIFY, INDICATE):
        heard.append(({VALUE: "val", NOTIFY: "ntf", INDICATE: "ind"}[kind], e.handle, data))
    elif kind == DONE:
        heard.append(("done", e.proc, e.status) + ((e.len,) if e.proc == P_MTU else ()))


GATTFN = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(on_gatt)
C.c_void_p.in_dll(lib, "ubt_gatt_fn").value = C.cast(GATTFN, C.c_void_p).value
la, lb = E.le_link()
LA, LB = Conn.from_address(la), Conn.from_address(lb)


def att_pdus(ctrl, start):
    return [f[4:] for f in E.frames(ctrl, start) if struct.unpack_from("<H", f, 2)[0] == 4]


def go(call, *args):
    heard.clear()
    rc = call(la, *args)
    E.settle(20)
    return rc, list(heard)


u16 = lambda v: struct.pack("<H", v)  # noqa: E731

# ---- discovery at the default MTU (23: several requests each) ---------------------------------------------
mb = len(cb.sent)
rc, got = go(services, None, 0)
want = [("svc", 1, 5, u16(0x1800)), ("svc", 6, 9, u16(0x1801)), ("svc", 10, 13, u16(0x180F)),
        ("svc", 14, 18, U128), ("svc", 19, LAST, u16(0xFFF0)), ("done", P_SERVICES, 0)]
check("every primary service, with its handles and UUID", (rc, got), (0, want))
check("in several responses (MTU 23), the 128-bit one alone", len([p for p in att_pdus(cb, mb) if p[0] == 0x11]), 3)
check("services with the battery UUID", go(services, u16(0x180F), 2)[1], [("svc", 10, 13, u16(0x180F)),
                                                                            ("done", P_UUID, 0)])
check("with a 128-bit UUID", go(services, U128, 16)[1], [("svc", 14, 18, U128), ("done", P_UUID, 0)])
check("one nobody has", go(services, u16(0x1234), 2)[1], [("done", P_UUID, 0)])
check("characteristics of the battery service", go(chars, 10, 13)[1],
      [("chr", 11, READ | NOTIFY_P, 12, u16(0x2A19)), ("done", P_CHARS, 0)])
got = go(chars, 1, 0xFFFF)[1]
check("all characteristics: name, appearance, service changed, level, custom, three more",
      [(g[1], g[3]) for g in got if g[0] == "chr"], [(2, 3), (4, 5), (7, 8), (11, 12), (15, 16), (20, 21), (22, 23),
                                                      (24, 25)])
check("the custom one's 128-bit UUID and properties", [g for g in got if g[0] == "chr" and g[1] == 15],
      [("chr", 15, READ | WRITE | WRITE_NR | INDICATE_P | SIGNED, 16, C128)])
check("descriptors after the custom value", go(descs, 17, 18)[1],
      [("dsc", 17, u16(0x2902)), ("dsc", 18, u16(0x2901)), ("done", P_DESCS, 0)])
check("find information over 16- and 128-bit types: one format per response",
      [g[1] for g in go(descs, 14, 18)[1] if g[0] == "dsc"], [14, 15, 16, 17, 18])

# ---- reading ----------------------------------------------------------------------------------------------
check("the battery level", go(read, 12)[1], [("val", 12, b"\x4d"), ("done", P_READ, 0)])
check("the device name", go(read, 3)[1][0], ("val", 3, b"Utk B"))
mb = len(cb.sent)
check("300 bytes at MTU 23: read whole, blob by blob", go(read, 16)[1], [("val", 16, LONG), ("done", P_READ, 0)])
check("one Read and 13 Read Blobs", [p[0] for p in att_pdus(cb, mb)], [0x0B] + [0x0D] * 13)
check("two values in one Read Multiple", go(read_mult, u16(3) + u16(12), 2)[1],
      [("val", 0, b"Utk B\x4d"), ("done", P_MULT, 0)])
check("from Python's read function", go(read, 25)[1][0], ("val", 25, b"from Python"))
check("no such handle", go(read, 99)[1], [("done", P_READ, 0x01)])
check("the CCCD of a link that set none: 0", go(read, 13)[1][0], ("val", 13, b"\x00\x00"))

# ---- MTU ----------------------------------------------------------------------------------------------------
check("MTU exchanged: 517 both ways", (go(mtu)[1], struct.unpack_from("<H", C.string_at(LA.att + AL[1], 2))[0],
                                      struct.unpack_from("<H", C.string_at(LB.att + AL[1], 2))[0]),
      ([("done", P_MTU, 0, 517)], 517, 517))
mb = len(cb.sent)
check("now one Read", (go(read, 16)[1][0], [p[0] for p in att_pdus(cb, mb)]), (("val", 16, LONG), [0x0B]))

# ---- writing --------------------------------------------------------------------------------------------------
check("a Write Request", go(write, 16, b"hello", 5)[1], [("done", P_WRITE, 0)])
check("kept", go(read, 16)[1][0], ("val", 16, b"hello"))
E.radio  # (keep the link at MTU 23 for a long write: a new link)
E.disconnect(la, 0x13)
E.settle()
la, lb = E.le_link()
LA, LB = Conn.from_address(la), Conn.from_address(lb)
BIG = bytes((i * 7 + 1) & 0xFF for i in range(400))
ma, mb = len(ca.sent), len(cb.sent)
check("400 bytes at MTU 23: prepared writes, then Execute", go(write, 16, BIG, 400)[1], [("done", P_LONG, 0)])
check("23 Prepare Writes of 18, one Execute", [(p[0], len(p)) for p in att_pdus(ca, ma)][:1] +
      [(len([p for p in att_pdus(ca, ma) if p[0] == 0x16]), len([p for p in att_pdus(ca, ma) if p[0] == 0x18]))],
      [(0x16, 23), (23, 1)])
check("written whole", go(read, 16)[1][0], ("val", 16, BIG))
mb = len(cb.sent)
check("a Write Command: no answer", (go(write_cmd, 16, b"cmd", 3)[1], att_pdus(cb, mb)), ([], []))
check("but written", go(read, 16)[1][0], ("val", 16, b"cmd"))
check("to Python's write function", (go(write, 25, b"py", 2)[1], seen_writes[-1:]), ([("done", P_WRITE, 0)], [b"py"]))
check("which can refuse", go(write, 25, b"no", 2)[1], [("done", P_WRITE, 0x80)])
check("a value that does not take writes", go(write, 12, b"x", 1)[1], [("done", P_WRITE, 0x03)])
check("more than its maximum", go(write, 23, bytes(9), 9)[1], [("done", P_WRITE, 0x05)])

# ---- security ---------------------------------------------------------------------------------------------------
check("encrypted only, on a plain link, no bond: Insufficient Authentication", go(read, 21)[1],
      [("done", P_READ, 0x05)])
check("authenticated only: the same", go(write, 23, b"\x01", 1)[1], [("done", P_WRITE, 0x05)])
for ad in (a, b):
    C.c_uint8.from_address(ad + G[1]).value = 3
    C.c_uint8.from_address(ad + G[2]).value = 1
rng_state = [1]


def give_random(p, n):
    out = bytes((rng_state[0] * 131 + i * 17) & 0xFF for i in range(n))
    rng_state[0] += 1
    C.memmove(p, out, n)
    return 0


RAND = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_uint32)(give_random)
C.c_void_p.in_dll(lib, "ubt_random_fn").value = C.cast(RAND, C.c_void_p).value
pair(la)
E.settle(30)
check("paired (Just Works) and encrypted", LA.sec, 1)
check("now the encrypted one reads", go(read, 21)[1][0], ("val", 21, b"secret"))
check("authentication still missing for the other", go(write, 23, b"\x01", 1)[1], [("done", P_WRITE, 0x05)])
E.disconnect(la, 0x13)
E.settle()
la, lb = E.le_link()
LA, LB = Conn.from_address(la), Conn.from_address(lb)
check("bonded but not encrypted yet: Insufficient Encryption", go(read, 21)[1], [("done", P_READ, 0x0F)])

# ---- signed writes (the link not encrypted) ------------------------------------------------------------------------
csrk = bytes(C.string_at(C.addressof(C.c_uint8.in_dll(lib, "ubt_local_csrk")), 16))
counter = C.c_uint32.in_dll(lib, "ubt_sign_counter").value
ma = len(ca.sent)
go(write_signed, 16, b"signed!", 7)
pdu = att_pdus(ca, ma)[0]
m = pdu[:-8]
mac = rev(R.cmac(rev(csrk), rev(m)))[8:]
check("Signed Write: opcode, handle, value, counter, the MAC of them", (pdu[:10], pdu[10:14], pdu[14:]),
      (b"\xd2" + u16(16) + b"signed!", struct.pack("<I", counter), mac))
check("checked with the bond's CSRK and written", go(read, 16)[1][0], ("val", 16, b"signed!"))
E.inject(cb, LB.handle, struct.pack("<HH", len(pdu), 4) + pdu)
go(write, 16, b"plain", 5)
E.inject(cb, LB.handle, struct.pack("<HH", len(pdu), 4) + pdu)
check("the same again (an old counter): not written", go(read, 16)[1][0], ("val", 16, b"plain"))
bad = bytearray(att_pdus(ca, len(ca.sent) - 0) or pdu)
tampered = pdu[:3] + b"SIGNED!" + pdu[10:]
tampered = tampered[:10] + struct.pack("<I", counter + 50) + tampered[14:]
E.inject(cb, LB.handle, struct.pack("<HH", len(tampered), 4) + tampered)
check("a changed value or counter: the MAC fails, not written", go(read, 16)[1][0], ("val", 16, b"plain"))

# ---- notifications and indications ------------------------------------------------------------------------------------
check("not subscribed: nothing sent", notify(lb, 12, b"\x37", 1), 1)
check("subscribing to notifications", go(subscribe, 13, 1)[1], [("done", P_WRITE, 0)])
heard.clear()
check("notified", (notify(lb, 12, b"\x37", 1), E.settle(), heard), (0, None, [("ntf", 12, b"\x37")]))
check("an indication not asked for", indicate(lb, 16, b"i", 1), 1)
go(subscribe, 17, 2)
heard.clear()
mc = len(ca.sent)
check("indicated, and confirmed", (indicate(lb, 16, b"ind", 3), E.settle(), heard, [p[0] for p in att_pdus(ca, mc)]),
      (0, None, [("ind", 16, b"ind")], [0x1E]))
ca.deaf = True
indicate(lb, 16, b"one", 3)
check("one indication at a time", indicate(lb, 16, b"two", 3), -3)
ca.deaf = False
E.now[0] += 30001
E.settle()
check("unconfirmed for 30 s: ATT is over on that link", notify(lb, 12, b"\x01", 1), -2)

# ---- by hand, to B ------------------------------------------------------------------------------------------------------
E.disconnect(la, 0x13)
E.settle()
la, lb = E.le_link()
LA, LB = Conn.from_address(la), Conn.from_address(lb)
ca.deaf = True


def ask(pdu):
    mark = len(cb.sent)
    E.inject(cb, LB.handle, struct.pack("<HH", len(pdu), 4) + pdu)
    return att_pdus(cb, mark)


def err(op, h, e):
    return [bytes([1, op]) + u16(h) + bytes([e])]


check("a request nobody knows: Request Not Supported", ask(b"\x30\x01\x00"), err(0x30, 0, 6))
check("a command nobody knows: nothing", ask(b"\x70\x01\x00"), [])
check("a group type that is not a service", ask(b"\x10" + u16(1) + u16(0xFFFF) + u16(0x2803)), err(0x10, 1, 0x10))
check("a range starting at 0", ask(b"\x08" + u16(0) + u16(5) + u16(0x2803)), err(0x08, 0, 1))
check("a range backwards", ask(b"\x04" + u16(9) + u16(5)), err(0x04, 9, 1))
check("past the last handle: not found", ask(b"\x04" + u16(26) + u16(0xFFFF)), err(0x04, 26, 0x0A))
check("a Read of the wrong length", ask(b"\x0a\x01"), err(0x0A, 0, 4))
check("a Read Blob past the end", ask(b"\x0c" + u16(3) + u16(6)), err(0x0C, 3, 7))
check("Read By Type with a 128-bit type: the value's handle and value", ask(b"\x08" + u16(1) + u16(0xFFFF) + C128),
      [bytes([0x09, 2 + 5]) + u16(16) + b"plain"])
replies = [ask(b"\x16" + u16(16) + u16(i) + b"x")[0][0] for i in range(33)]
check("33 Prepare Writes: the 33rd refused, queue full", (replies[:32] == [0x17] * 32, replies[32]), (True, 0x01))
check("Execute with cancel: dropped", ask(b"\x18\x00"), [b"\x19"])
check("a CCCD written with 3 bytes", ask(b"\x12" + u16(13) + b"\x01\x00\x00"), err(0x12, 13, 0x0D))
check("a CCCD with a bit that means nothing", ask(b"\x12" + u16(13) + b"\x04\x00"), err(0x12, 13, 0xFD))
check("Exchange MTU of 10: 23 kept", (ask(b"\x02" + u16(10)), struct.unpack_from("<H", C.string_at(LB.att + AL[1], 2))[0]),
      ([b"\x03" + u16(517)], 23))
ca.deaf = False

# ---- the client's timeout ---------------------------------------------------------------------------------------------------
cb.deaf = True
heard.clear()
read(la, 3)
E.settle()
E.now[0] += 30001
E.settle()
cb.deaf = False
check("no answer in 30 s: done with the timeout", heard, [("done", P_READ, 0x100)])
check("and no more ATT on the link", read(la, 3), -2)

# ---- everything given back -------------------------------------------------------------------------------------------------------
E.disconnect(la, 0x13)
E.settle()
E.remove(a)
E.remove(b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_gatt: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

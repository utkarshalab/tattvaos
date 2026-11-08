"""Service Discovery Protocol tests (sdp/sdp.asm): our client against our
server over a BR/EDR link, and requests made by hand on a channel to PSM 1.

usage: python3 test_sdp.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env, BASIC  # noqa: E402

E = Env(sys.argv[1])
check, lib, SA = E.check, E.lib, E.SA
fn = E.fn
sdp_init = fn("ubt_sdp_init", None)
sdp_add = fn("ubt_sdp_add", C.c_uint32, C.c_char_p, C.c_uint32)
sdp_remove = fn("ubt_sdp_remove", None, C.c_uint32)
make_record = fn("ubt_sdp_rfcomm_record", C.c_uint32, C.c_uint32, C.c_uint32, C.c_char_p, C.c_uint32, C.c_void_p)
sdp_query = fn("ubt_sdp_query", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32, C.c_uint32, C.c_uint32)
sdp_close = fn("ubt_sdp_close", None, C.c_void_p)
sdp_attr = fn("ubt_sdp_attr", C.c_uint64, C.c_void_p, C.c_uint32, C.c_uint32)
sdp_channel = fn("ubt_sdp_rfcomm_channel", C.c_uint32, C.c_char_p, C.c_uint32)


# ---- data elements -------------------------------------------------------------------------------------
def elem(kind, body, size=None):
    if size is not None:
        return bytes([kind << 3 | size]) + body
    if len(body) < 256:
        return bytes([kind << 3 | 5, len(body)]) + body
    return bytes([kind << 3 | 6]) + struct.pack(">H", len(body)) + body


def u8(v):
    return elem(1, bytes([v]), 0)


def u16(v):
    return elem(1, struct.pack(">H", v), 1)


def u32(v):
    return elem(1, struct.pack(">I", v), 2)


def id16(v):
    return elem(3, struct.pack(">H", v), 1)


def id128(v):
    return elem(3, struct.pack(">I", v) + bytes.fromhex("00001000800000805F9B34FB"), 4)


def txt(s):
    return elem(4, s)


def seq(*items):
    return elem(6, b"".join(items))


def parse(data, i=0):
    """One element: sequences become lists, the rest (kind, body)."""
    h = data[i]
    kind, size = h >> 3, h & 7
    if size < 5:
        n, hl = (0 if kind == 0 else 1 << size), 1
    else:
        hl = {5: 2, 6: 3, 7: 5}[size]
        n = int.from_bytes(data[i + 1:i + hl], "big")
    body = data[i + hl:i + hl + n]
    if kind in (6, 7):
        out, j = [], 0
        while j < len(body):
            v, j = parse(body, j)
            out.append(v)
        return out, i + hl + n
    return (kind, body), i + hl + n


def as_dict(lst):
    return {int.from_bytes(lst[k][1], "big"): lst[k + 1] for k in range(0, len(lst), 2)}


# ---- records -----------------------------------------------------------------------------------------------
sdp_init()
buf = C.create_string_buffer(104)
n = make_record(0x1101, 3, b"Serial Port", 11, buf)
want = seq(u16(1), seq(id16(0x1101)),
           u16(4), seq(seq(id16(0x0100)), seq(id16(0x0003), u8(3))),
           u16(5), seq(id16(0x1002)),
           u16(0x100), txt(b"Serial Port"))
check("a serial-port record, made", buf.raw[:n], want)
h_spp = sdp_add(buf.raw[:n], n)
check("added: the first handle", h_spp, 0x10000)
other = seq(u16(1), seq(id128(0x1234)), u16(4), seq(seq(id16(0x0100))), u16(0x100), txt(b"Other"))
h_other = sdp_add(other, len(other))
big = [seq(u16(1), seq(id16(0x1200 + i)), u16(4), seq(seq(id16(0x0100))), u16(0x100), txt(bytes([65 + i]) * 300))
       for i in range(4)]
h_big = [sdp_add(r, len(r)) for r in big]
check("more records, handles in order", (h_other, h_big), (0x10001, [0x10002, 0x10003, 0x10004, 0x10005]))
check("not one sequence: refused", (sdp_add(u16(1), 3), sdp_add(seq(u16(1)) + b"x", 6)), (0, 0))

# ---- the client ------------------------------------------------------------------------------------------------
results = []
SDPFN = C.CFUNCTYPE(None, C.c_void_p, C.c_int32, C.c_void_p, C.c_uint32)(
    lambda conn, status, p, n: results.append((status, C.string_at(p, n) if p else b"")))
C.c_void_p.in_dll(lib, "ubt_sdp_fn").value = C.cast(SDPFN, C.c_void_p).value
ka, kb = E.link()


def ask(uuids, first=0, last=0xFFFF):
    results.clear()
    rc = sdp_query(ka, b"".join(struct.pack("<H", u) for u in uuids), len(uuids), first, last)
    E.settle(20)
    return rc, list(results)


def sdp_pdus(ctrl, start, pdu):
    out = []
    for f in E.frames(ctrl, start):
        body = f[4:]
        if struct.unpack_from("<H", f, 2)[0] >= 0x40 and body and body[0] == pdu:
            out.append(body)
    return out


ma = len(E.ca.sent)
rc, got = ask([0x1101])
check("query for serial port: one answer, success", (rc, len(got), got[0][0] if got else None), (0, 1, 0))
records, _ = parse(got[0][1])
check("one record", len(records), 1)
r = as_dict(records[0])
check("its handle (attribute 0) put first by the server", (r[0], records[0][0]), ((1, struct.pack(">I", h_spp)), (1, b"\x00\x00")))
check("its service class and name", (r[1], r[0x100]), ([(3, struct.pack(">H", 0x1101))], (4, b"Serial Port")))
check("its RFCOMM channel, found in the answer", sdp_channel(got[0][1], len(got[0][1])), 3)
check("one request was enough", len(sdp_pdus(E.ca, ma, 6)), 1)

rc, got = ask([0x1234])
check("a 16-bit UUID finds a record that has it as 128 bits", [as_dict(x)[0x100] for x in parse(got[0][1])[0]],
      [(4, b"Other")])

ma = len(E.ca.sent)
rc, got = ask([0x0100])
lists = parse(got[0][1])[0]
check("every record has L2CAP: all six, the long ones whole",
      [as_dict(x)[0x100][1][:1] for x in lists], [b"S", b"O", b"A", b"B", b"C", b"D"])
check("their names whole (300 bytes)", [len(as_dict(x)[0x100][1]) for x in lists[2:]], [300] * 4)
check("asked again with continuation until all came", len(sdp_pdus(E.ca, ma, 6)) > 1, True)

rc, got = ask([0x1101], 0x0100, 0x0100)
check("only the name asked for", parse(got[0][1])[0], [[(1, b"\x01\x00"), (4, b"Serial Port")]])
rc, got = ask([0x9999])
check("nobody has it: an empty answer", parse(got[0][1])[0], [])

# ---- helpers on what came back ----------------------------------------------------------------------------------
lst = seq(u16(1), seq(id16(0x1101)), u16(0x100), txt(b"Name"))
lbuf = C.create_string_buffer(lst, len(lst))
p = sdp_attr(C.addressof(lbuf), len(lst), 0x100)
check("an attribute's value found in a list", C.string_at(p, 6) if p else None, txt(b"Name"))
check("one not there", sdp_attr(C.addressof(lbuf), len(lst), 0x200), 0)
check("no RFCOMM in a list without it", sdp_channel(lst, len(lst)), 0)

# ---- by hand, on a channel of our own ------------------------------------------------------------------------------
SA.data.clear()
SA.events.clear()
ch = E.l2connect(ka, 1, BASIC, C.byref(SA.ops), None)
E.settle()


def raw(pdu, params, tid=0x0101):
    SA.data.clear()
    msg = bytes([pdu]) + struct.pack(">HH", tid, len(params)) + params
    E.l2send(ch, msg, len(msg))
    E.settle()
    return SA.data[-1][1] if SA.data else None


def error_of(rsp):
    return (rsp[0], struct.unpack(">H", rsp[5:7])[0]) if rsp else None


rsp = raw(0x02, seq(id16(0x1101)) + struct.pack(">H", 10) + b"\x00")
check("Service Search: one handle", rsp[5:] if rsp else None, struct.pack(">HHI", 1, 1, h_spp) + b"\x00")
rsp = raw(0x02, seq(id16(0x0100)) + struct.pack(">H", 2) + b"\x00")
check("at most two wanted: two", struct.unpack(">HH", rsp[5:9]) if rsp else None, (2, 2))
rsp = raw(0x04, struct.pack(">IH", h_spp, 100) + seq(u32(0x0000FFFF)) + b"\x00")
check("Service Attribute: the whole record's list", parse(rsp[7:])[0] if rsp else None, records[0])
rsp = raw(0x04, struct.pack(">IH", 0x99999, 100) + seq(u16(1)) + b"\x00")
check("an unknown handle: error 2", error_of(rsp), (1, 2))
rsp = raw(0x04, struct.pack(">IH", h_spp, 100) + b"\x00")
check("no ID list: error 3", error_of(rsp), (1, 3))
rsp = raw(0x06, b"\x35")
check("a pattern that does not parse: error 3", error_of(rsp), (1, 3))
msg = bytes([0x02]) + struct.pack(">HH", 7, 50) + b"\x00"
SA.data.clear()
E.l2send(ch, msg, len(msg))
E.settle()
check("a length that does not match: error 4", error_of(SA.data[-1][1]) if SA.data else None, (1, 4))
rsp = raw(0x04, struct.pack(">IH", h_spp, 100) + seq(u16(1)) + b"\x05abcde")
check("a continuation not ours: error 5", error_of(rsp), (1, 5))
rsp = raw(0x30, b"")
check("an unknown request: error 3", error_of(rsp), (1, 3))
check("the answer keeps the request's transaction ID", raw(0x30, b"", tid=0xBEEF)[1:3], b"\xbe\xef")
# small pieces: at most 7 bytes of answer each, followed to the end
pieces, cont = b"", b"\x00"
for _ in range(40):
    rsp = raw(0x04, struct.pack(">IH", h_spp, 7) + seq(u32(0x0000FFFF)) + cont)
    count = struct.unpack(">H", rsp[5:7])[0]
    pieces += rsp[7:7 + count]
    cont = rsp[7 + count:]
    if cont == b"\x00":
        break
check("seven bytes at a time with continuation: the same list", parse(pieces)[0], records[0])

# ---- removing, closing, everything given back ---------------------------------------------------------------------
sdp_remove(h_spp)
rc, got = ask([0x1101])
check("removed: not found any more", parse(got[0][1])[0], [])
E.l2disconnect(ch)
sdp_close(ka)
E.settle()
E.disconnect(ka, 0x13)
E.settle()
E.remove(E.a)
E.remove(E.b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_sdp: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

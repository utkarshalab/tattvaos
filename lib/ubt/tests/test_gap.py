"""Discovery, names, advertising and scanning (gap/gap.asm): two of our
stacks on the virtual radio, and reports made by hand.

usage: python3 test_gap.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env  # noqa: E402

E = Env(sys.argv[1])
check, a, b, ca, cb = E.check, E.a, E.b, E.ca, E.cb
FOUND, INQUIRY_DONE, NAME = 1, 2, 3
LE, LE_RSP, BR = 1, 2, 3


class Found(C.Structure):
    _fields_ = [("kind", C.c_uint8), ("addr_type", C.c_uint8), ("event_type", C.c_uint16), ("addr", C.c_uint8 * 6),
                ("rssi", C.c_int8), ("pad", C.c_uint8), ("cls", C.c_uint32), ("data_len", C.c_uint32),
                ("pad3", C.c_uint32), ("data", C.c_uint64), ("tx_power", C.c_int8), ("phy", C.c_uint8),
                ("sid", C.c_uint8), ("pad2", C.c_uint8 * 5)]


class Name(C.Structure):
    _fields_ = [("addr", C.c_uint8 * 6), ("status", C.c_uint8), ("pad", C.c_uint8), ("len", C.c_uint32),
                ("pad2", C.c_uint32), ("name", C.c_uint64)]


L = list((C.c_uint32 * 16).in_dll(E.lib, "ubt_gap_layout"))
check("the records as the tests know them", (L[12], L[13]), (C.sizeof(Found), C.sizeof(Name)))
heard = {a: [], b: []}


def on_gap(adapter, kind, rec):
    if kind == FOUND:
        f = Found.from_address(rec)
        heard[adapter].append(("found", f.kind, bytes(f.addr), f.addr_type, f.event_type, f.rssi, f.cls,
                               C.string_at(f.data, f.data_len) if f.data_len else b"", f.tx_power, f.phy, f.sid))
    elif kind == NAME:
        n = Name.from_address(rec)
        heard[adapter].append(("name", bytes(n.addr), n.status, C.string_at(n.name, n.len)))
    else:
        heard[adapter].append((kind,))


GAP = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(on_gap)
for ad in (a, b):
    C.c_void_p.from_address(ad + L[0]).value = C.cast(GAP, C.c_void_p).value
fn = E.fn
advertise = fn("ubt_le_advertise", C.c_int32, C.c_void_p, C.c_uint32, C.c_char_p, C.c_uint32, C.c_char_p, C.c_uint32)
adv_stop = fn("ubt_le_advertise_stop", C.c_int32, C.c_void_p)
scan = fn("ubt_le_scan", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
scan_stop = fn("ubt_le_scan_stop", C.c_int32, C.c_void_p)
inquiry = fn("ubt_inquiry", C.c_int32, C.c_void_p, C.c_uint32, C.c_uint32)
remote_name = fn("ubt_remote_name", C.c_int32, C.c_void_p, C.c_char_p)
set_scan = fn("ubt_set_scan", C.c_int32, C.c_void_p, C.c_uint32)
set_name = fn("ubt_set_name", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
set_class = fn("ubt_set_class", C.c_int32, C.c_void_p, C.c_uint32)
set_eir = fn("ubt_set_eir", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
def ad(*fields):
    return b"".join(bytes([len(v) + 1, t]) + v for t, v in fields)


find2 = E.lib.ubt_ad_find
find2.restype = C.c_uint64
find2.argtypes = [C.c_void_p, C.c_uint32, C.c_uint32]


def find(data, t):
    """ubt_ad_find on a copy: the value it points at, as long as its field says."""
    buf = C.create_string_buffer(data, len(data))
    p = find2(C.addressof(buf), len(data), t)
    if not p:
        return None
    off = p - C.addressof(buf)
    return data[off:off + data[off - 2] - 1]


# ---- advertising data ---------------------------------------------------------------------------
data = ad((0x01, b"\x06"), (0x09, b"Utk B"), (0xFF, b"\x34\x12hi"))
check("a field found by type", (find(data, 0x09), find(data, 0xFF), find(data, 0x01)), (b"Utk B", b"\x34\x12hi", b"\x06"))
check("a type not there", find(data, 0x03), None)
check("a field running past the end: not found", find(b"\x05\x09ab", 0x09), None)
check("zero padding ends it", find(b"\x00\x00\x03\x09ab", 0x09), None)

# ---- advertising and scanning ----------------------------------------------------------------------
rsp = ad((0x0A, b"\x04"))
check("B advertises", advertise(b, 0, data, len(data), rsp, len(rsp)), 0)
check("the commands B's controller got: parameters, data, response, enable",
      [c for c in cb.commands if c in (0x2006, 0x2008, 0x2009, 0x200A)], [0x2006, 0x2008, 0x2009, 0x200A])
check("what B's controller has", (cb.advertising, cb.adv_type, cb.adv_data, cb.scan_rsp), (True, 0, data, rsp))
check("A scans passively", scan(a, 0, 0), 0)
E.settle()
check("A hears B's advertisement", heard[a], [("found", LE, E.B_ADDR, 0, 0, -50, 0, data, 127, 0, 0)])
heard[a].clear()
scan_stop(a)
check("actively", scan(a, 1, 0), 0)
E.settle()
check("now with the scan response", [(h[1], h[4], h[7]) for h in heard[a]], [(LE, 0, data), (LE_RSP, 4, rsp)])
heard[a].clear()
scan_stop(a)
adv_stop(b)
scan(a, 1, 1)
E.settle()
check("B stopped: nothing", heard[a], [])
advertise(b, 3, data, len(data), None, 0)
advertise(b, 3, data, len(data), None, 0)
E.settle()
check("not connectable, the same twice with duplicates dropped: one report, no response",
      [(h[1], h[4]) for h in heard[a]], [(LE, 3)])
scan_stop(a)
adv_stop(b)
check("too much data: cut to 31", (advertise(b, 3, bytes(40), 40, None, 0), len(cb.adv_data)), (0, 31))
adv_stop(b)

# ---- reports made by hand ----------------------------------------------------------------------------
heard[a].clear()
two = bytes([0x02, 2]) + bytes([0, 1]) + bytes([1, 2, 3, 4, 5, 6]) + bytes([3]) + b"\x02\x01\x06" + bytes([0xC4]) \
      + bytes([4, 0]) + bytes([7, 7, 7, 7, 7, 7]) + bytes([0]) + bytes([0xB0])
E.radio.inject_event(ca, 0x3E, two)
E.settle()
check("two reports in one event, a random address, an empty response",
      [(h[1], h[2], h[3], h[5], h[7]) for h in heard[a]],
      [(LE, bytes([1, 2, 3, 4, 5, 6]), 1, -60, b"\x02\x01\x06"), (LE_RSP, bytes([7] * 6), 0, -80, b"")])
heard[a].clear()
E.radio.inject_event(ca, 0x3E, bytes([0x02, 1, 0, 0]) + bytes(6) + bytes([30]) + b"short")
E.settle()
check("a report longer than its event: dropped", heard[a], [])
ext = bytes([0x0D, 1]) + struct.pack("<H", 0x0013) + bytes([1]) + bytes([9, 8, 7, 6, 5, 4]) + bytes([1, 2, 3])
ext += struct.pack("<bb", 4, -40) + struct.pack("<H", 0) + bytes([0]) + bytes(6) + bytes([5]) + b"\x04\x09abc"
E.radio.inject_event(ca, 0x3E, ext)
ext_rsp = bytes([0x0D, 1]) + struct.pack("<H", 0x001B) + bytes([0]) + bytes([9] * 6) + bytes([1, 0, 0xFF])
ext_rsp += struct.pack("<bb", 127, -70) + struct.pack("<H", 0) + bytes([0]) + bytes(6) + bytes([0])
E.radio.inject_event(ca, 0x3E, ext_rsp)
E.settle()
check("extended reports: properties, PHY, SID, TX power, RSSI, data; a scan response",
      [(h[1], h[2], h[3], h[4], h[5], h[7], h[8], h[9], h[10]) for h in heard[a]],
      [(LE, bytes([9, 8, 7, 6, 5, 4]), 1, 0x13, -40, b"\x04\x09abc", 4, 2, 3),
       (LE_RSP, bytes([9] * 6), 0, 0x1B, -70, b"", 127, 0, 0xFF)])

# ---- BR/EDR: names, class, EIR, inquiry -------------------------------------------------------------------
eir = ad((0x09, b"Utkarsha B"), (0x03, b"\x0b\x11"))
check("B made discoverable and connectable, with a name, a class and EIR",
      (set_scan(b, 3), set_name(b, b"Utkarsha B", 10), set_class(b, 0x240404), set_eir(b, eir, len(eir))), (0, 0, 0, 0))
check("what B's controller has", (cb.scan_enable, cb.name, cb.cls, cb.eir[:len(eir)], len(cb.eir)),
      (3, b"Utkarsha B", 0x240404, eir, 240))
heard[a].clear()
check("A asks who is there", inquiry(a, 8, 0), 0)
E.settle()
check("the inquiry asked for extended results", ca.inquiry_mode, 2)
got = heard[a]
check("B found: class, RSSI, its EIR; then the end", [(g[0], g[1], g[2], g[6], g[5], g[7][:len(eir)]) for g in got[:1]]
      + got[1:], [("found", BR, E.B_ADDR, 0x240404, -50, eir), (INQUIRY_DONE,)])
check("its name, from its EIR", find(got[0][7], 0x09), b"Utkarsha B")
heard[a].clear()
set_scan(b, 2)
inquiry(a, 8, 0)
E.settle()
check("B no longer discoverable: only the end", heard[a], [(INQUIRY_DONE,)])
set_scan(b, 3)
heard[a].clear()
for mode, code in ((0, 0x02), (1, 0x22)):
    ca.inquiry_mode = mode
    ca.gap_command(0x0401, struct.pack("<I", 0x9E8B33)[:3] + b"\x08\x00")     # the controller as if in that mode
E.settle()
check("standard and RSSI results", [(g[1], g[2], g[5], g[6]) for g in heard[a] if g[0] == "found"],
      [(BR, E.B_ADDR, 127, 0x240404), (BR, E.B_ADDR, -50, 0x240404)])
heard[a].clear()
E.radio.inject_event(ca, 0x22, bytes([2]) + bytes([1] * 6) + bytes(7) + b"\xD8" + bytes([2] * 6) + bytes(2)
                     + bytes([1, 2, 3]) + b"\x00\x00\xE2")
E.settle()
check("two responses in one event", [(g[2], g[5], g[6]) for g in heard[a]],
      [(bytes([1] * 6), -40, 0), (bytes([2] * 6), -30, 0x030201)])
heard[a].clear()
check("B's name asked", remote_name(a, E.B_ADDR), 0)
E.settle()
check("and given", heard[a], [("name", E.B_ADDR, 0, b"Utkarsha B")])
heard[a].clear()
remote_name(a, bytes([0x33] * 6))
E.settle()
check("nobody there: page timeout, no name", heard[a], [("name", bytes([0x33] * 6), 4, b"")])
heard[a].clear()
E.radio.inject_event(ca, 0x07, b"\x00" + bytes(6) + b"x" * 248)
E.settle()
check("a name using all 248 bytes", [(h[2], len(h[3])) for h in heard[a]], [(0, 248)])

# ---- everything given back ----------------------------------------------------------------------------------------
E.remove(a)
E.remove(b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_gap: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

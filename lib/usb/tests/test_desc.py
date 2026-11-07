"""Descriptor parsers (core/desc.asm): known descriptors, malformed ones,
and a fuzz pass checked against a reference parser written here.

usage: python3 test_desc.py path/to/usb.so [fuzz rounds]
"""
import ctypes as C
import os
import random
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import usb_gen as G  # noqa: E402

lib = C.CDLL(sys.argv[1])
ROUNDS = int(sys.argv[2]) if len(sys.argv) > 2 else 20000
EDESC, ETRUNC, ETOOMANY = -1, -2, -3
WARN_EP_ORPHAN, WARN_EP_COUNT, WARN_IFACES, WARN_IADS = 1, 2, 4, 8
MAX_IFACES, MAX_EPS, MAX_IADS = 32, 64, 8


class Iface(C.Structure):
    _fields_ = [(n, C.c_uint8) for n in ("number", "alt", "cls", "sub", "proto", "string", "num_ep", "ep_count",
                                         "first_ep", "func", "hid_country", "hid_count")] + \
               [("hid_report_len", C.c_uint16), ("body_off", C.c_uint16), ("body_len", C.c_uint16),
                ("pad", C.c_uint32)]


class Ep(C.Structure):
    _fields_ = [("address", C.c_uint8), ("attributes", C.c_uint8), ("max_packet", C.c_uint16),
                ("interval", C.c_uint8), ("iface", C.c_uint8), ("ss_burst", C.c_uint8), ("ss_attr", C.c_uint8),
                ("ss_bpi", C.c_uint32), ("refresh", C.c_uint8), ("synch", C.c_uint8), ("pad", C.c_uint16)]


class Iad(C.Structure):
    _fields_ = [(n, C.c_uint8) for n in ("first", "count", "cls", "sub", "proto", "string")] + [("pad", C.c_uint16)]


class Config(C.Structure):
    _fields_ = [("total", C.c_uint16)] + [(n, C.c_uint8) for n in (
        "num_ifaces", "value", "string", "attributes", "max_power", "iface_count", "ep_count", "iad_count",
        "other", "warn")] + [("pad", C.c_uint32), ("ifaces", Iface * MAX_IFACES), ("eps", Ep * MAX_EPS),
                             ("iads", Iad * MAX_IADS)]


class Bos(C.Structure):
    _fields_ = [(n, C.c_uint8) for n in ("caps", "lpm", "besl", "ss")] + [
        ("ss_speeds", C.c_uint16), ("ss_func", C.c_uint8), ("u1_lat", C.c_uint8), ("u2_lat", C.c_uint16),
        ("ssp", C.c_uint8), ("has_container", C.c_uint8), ("ssp_max_mbps", C.c_uint32),
        ("container", C.c_uint8 * 16)]


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


device_check = fn("usb_device_check", C.c_int32, C.c_char_p, C.c_uint32)
_config_parse = fn("usb_config_parse", C.c_int32, C.c_char_p, C.c_uint32, C.c_void_p)
_desc_next = fn("usb_desc_next", C.c_void_p, C.c_void_p, C.c_uint32, C.POINTER(C.c_uint32))
_string = fn("usb_string_utf8", C.c_int32, C.c_char_p, C.c_uint32, C.c_void_p, C.c_uint32)
_bos = fn("usb_bos_parse", C.c_int32, C.c_char_p, C.c_uint32, C.c_void_p)
assert C.sizeof(Iface) == 24 and C.sizeof(Ep) == 16 and C.sizeof(Config) == 16 + 768 + 1024 + 64
assert C.sizeof(Bos) == 32

CANARY = b"\xA5" * 64


def guarded(struct_type):
    """A record with canaries on both sides: a write outside it shows."""
    raw = C.create_string_buffer(CANARY + bytes(C.sizeof(struct_type)) + CANARY)
    return raw, struct_type.from_buffer(raw, len(CANARY))


def intact(raw, struct_type):
    b = raw.raw
    return b[:len(CANARY)] == CANARY and b[len(CANARY) + C.sizeof(struct_type):][:len(CANARY)] == CANARY


def config_parse(data, length=None):
    raw, cfg = guarded(Config)
    buf = C.create_string_buffer(bytes(data), max(len(data), 1))
    rc = _config_parse(buf, len(data) if length is None else length, C.addressof(cfg))
    assert intact(raw, Config), "config_parse wrote outside its record"
    return rc, cfg


def string_utf8(desc, size=128):
    raw = C.create_string_buffer(CANARY + bytes(size) + CANARY)
    rc = _string(bytes(desc), len(desc), C.addressof(raw) + len(CANARY), size)
    assert raw.raw[:64] == CANARY and raw.raw[64 + size:64 + size + 64] == CANARY, "string wrote outside"
    out = raw.raw[64:64 + size]
    return rc, (out[:rc] if rc >= 0 else None), (out[rc] if rc >= 0 else None)


def bos_parse(data):
    raw, b = guarded(Bos)
    rc = _bos(bytes(data), len(data), C.addressof(b))
    assert intact(raw, Bos), "bos_parse wrote outside its record"
    return rc, b


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


layout = (C.c_uint32 * 5).in_dll(lib, "usb_layout")
check("record sizes match usb.inc", list(layout),
      [C.sizeof(Iface), C.sizeof(Ep), C.sizeof(Iad), C.sizeof(Config), C.sizeof(Bos)])


# ---- device descriptor ------------------------------------------------------
check("a USB 2 device", device_check(G.device(), 18), 0)
check("SuperSpeed: 2^9", device_check(G.device(bcd_usb=0x0320, mps0=9), 18), 0)
check("SuperSpeed with 64", device_check(G.device(bcd_usb=0x0300, mps0=64), 18), EDESC)
check("packet size 7", device_check(G.device(mps0=7), 18), EDESC)
check("no configurations", device_check(G.device(configs=0), 18), EDESC)
check("only 8 bytes read", device_check(G.device(), 8), EDESC)
check("wrong type", device_check(b"\x12\x02" + G.device()[2:], 18), EDESC)

# ---- configuration: a keyboard ------------------------------------------------
rc, c = config_parse(G.KEYBOARD_CONFIG)
check("keyboard: parsed", (rc, c.total, c.num_ifaces, c.value, c.attributes, c.max_power, c.warn),
      (0, len(G.KEYBOARD_CONFIG), 1, 1, 0x80, 50, 0))
i = c.ifaces[0]
check("keyboard: the interface", (c.iface_count, i.number, i.cls, i.sub, i.proto, i.num_ep, i.ep_count,
                                  i.hid_report_len, i.func), (1, 0, 3, 1, 1, 1, 1, 63, 0xFF))
e = c.eps[0]
check("keyboard: the endpoint", (c.ep_count, e.address, e.attributes, e.max_packet, e.interval, e.iface),
      (1, 0x81, 3, 8, 10, 0))
check("keyboard: the body is the HID and endpoint descriptors", (i.body_off, i.body_len), (18, 9 + 7))

# ---- a composite device: audio (IAD), alternate settings, class descriptors -
AUDIO = G.config(
    G.iad(0, 2, 1, 0, 0x20, 4),
    G.interface(0, cls=1, sub=1, proto=0x20),
    G.cs(0x24, b"\x01\x00\x02\x01\x40\x00\x00"),
    G.interface(1, alt=0, cls=1, sub=2, proto=0x20),
    G.interface(1, alt=1, num_ep=2, cls=1, sub=2, proto=0x20),
    G.cs(0x24, b"\x01\x02\x00\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"),
    G.endpoint(0x01, 0x05, 0x0300 | 0x1000, 1, extra=b"\x00\x00"),
    G.cs(0x25, b"\x01\x00\x00\x00\x00\x00"),
    G.endpoint(0x82, 0x11, 4, 4, extra=b"\x03\x00"),
    G.interface(2, num_ep=1, cls=3),
    G.hid(100, country=33, extra=[(0x23, 7)]),
    G.endpoint(0x83, 3, 64, 1))
rc, c = config_parse(AUDIO)
check("composite: counts", (rc, c.iface_count, c.ep_count, c.iad_count, c.other, c.warn), (0, 4, 3, 1, 3, 0))
check("composite: alternate settings",
      [(c.ifaces[k].number, c.ifaces[k].alt, c.ifaces[k].num_ep, c.ifaces[k].first_ep) for k in range(4)],
      [(0, 0, 0, 0), (1, 0, 0, 0), (1, 1, 2, 0), (2, 0, 1, 2)])
check("composite: the association covers 0 and 1",
      ([c.ifaces[k].func for k in range(4)], c.iads[0].first, c.iads[0].count, c.iads[0].cls, c.iads[0].proto,
       c.iads[0].string), ([0, 0, 0, 0xFF], 0, 2, 1, 0x20, 4))
check("composite: high-bandwidth packet size, 9-byte audio endpoint",
      (c.eps[0].max_packet, c.eps[0].attributes, c.eps[1].refresh, c.eps[1].synch, c.eps[1].iface), (0x1300, 5, 3, 0, 2))
check("composite: HID with two class descriptors", (c.ifaces[3].hid_report_len, c.ifaces[3].hid_country,
                                                     c.ifaces[3].hid_count), (100, 33, 2))

# the body of interface 1 alt 1, walked as a class driver would
body = c.ifaces[2]
buf = C.create_string_buffer(AUDIO)
off = C.c_uint32(body.body_off)
kinds = []
while True:
    p = _desc_next(C.addressof(buf), body.body_off + body.body_len, C.byref(off))
    if not p:
        break
    kinds.append(C.c_uint8.from_address(p + 1).value)
check("usb_desc_next over an interface body", kinds, [0x24, 5, 0x25, 5])

# ---- SuperSpeed --------------------------------------------------------------
SS = G.config(G.interface(0, num_ep=2, cls=8, sub=6, proto=0x62),
              G.endpoint(0x81, 2, 1024, 0), G.ss_companion(15, 0x10, 0),
              G.endpoint(0x02, 2, 1024, 0), G.ss_companion(3),
              G.interface(1, num_ep=1, cls=0x0E, sub=2),
              G.endpoint(0x83, 5, 1024, 1), G.ss_companion(15, 2, 49152), G.ssp_isoc_companion(98304))
rc, c = config_parse(SS)
check("SuperSpeed companions", (rc, c.eps[0].ss_burst, c.eps[0].ss_attr, c.eps[1].ss_burst, c.eps[2].ss_bpi),
      (0, 15, 0x10, 3, 98304))

# ---- odd but usable -----------------------------------------------------------
rc, c = config_parse(G.config(G.endpoint(0x81, 3, 8, 1), G.interface(0, num_ep=2), G.endpoint(0x82, 3, 8, 1)))
check("orphan endpoint, short count", (rc, c.ep_count, c.warn & (WARN_EP_ORPHAN | WARN_EP_COUNT)),
      (0, 1, WARN_EP_ORPHAN | WARN_EP_COUNT))
rc, c = config_parse(G.config(G.interface(0), G.interface(1), num_ifaces=3))
check("bNumInterfaces wrong", (rc, c.warn), (0, WARN_IFACES))
rc, c = config_parse(G.config(G.ss_companion(), G.interface(0), G.ss_companion(4)))
check("companions with no endpoint are ignored", (rc, c.ep_count), (0, 0))
rc, c = config_parse(G.config(*[G.iad(k, 1, 0xEF) for k in range(10)], G.interface(9)))
check("more associations than kept", (rc, c.iad_count, c.warn & WARN_IADS, c.ifaces[0].func), (0, 8, WARN_IADS, 0xFF))

# ---- refused --------------------------------------------------------------------
kb = bytearray(G.KEYBOARD_CONFIG)
check("truncated read", config_parse(kb, 9)[0], ETRUNC)
check("not a configuration", config_parse(b"\x09\x04" + bytes(kb[2:]))[0], EDESC)
check("too short a header", config_parse(kb[:8])[0], EDESC)
bad = bytearray(kb)
bad[9] = 0
check("a zero-length descriptor", config_parse(bad)[0], EDESC)
bad = bytearray(kb)
bad[9] = 200
check("a descriptor past the end", config_parse(bad)[0], EDESC)
bad = bytearray(kb)
struct.pack_into("<H", bad, 2, 5)
check("wTotalLength under 9", config_parse(bad)[0], EDESC)
check("a short interface", config_parse(G.config(b"\x05\x04\x00\x00\x00"))[0], EDESC)
check("a short endpoint", config_parse(G.config(G.interface(0, num_ep=1), b"\x06\x05\x81\x03\x08\x00"))[0], EDESC)
check("one byte left over", config_parse(G.config(G.interface(0), b"\x09"))[0], EDESC)
many = G.config(*[G.interface(k) for k in range(33)])
check("33 interfaces", config_parse(many)[0], ETOOMANY)
many = G.config(G.interface(0, num_ep=65), *[G.endpoint(0x81, 2, 64, 0) for _ in range(65)])
check("65 endpoints", config_parse(many)[0], ETOOMANY)
rc, c = config_parse(G.config(G.interface(0, num_ep=64), *[G.endpoint(0x81, 2, 64, 0) for _ in range(64)]))
check("64 endpoints", (rc, c.ep_count, c.ifaces[0].ep_count), (0, 64, 64))
rc, c = config_parse(b"\x09\x02\x09\x00\x00\x01\x00\x80\x32")
check("no interfaces at all", (rc, c.iface_count, c.warn), (0, 0, 0))
check("wTotalLength shorter than what was read: the rest ignored",
      config_parse(G.KEYBOARD_CONFIG + b"\x00\x00\x00")[0], 0)

# ---- strings ---------------------------------------------------------------------
check("ASCII", string_utf8(G.string("USB Keyboard"))[:2], (12, b"USB Keyboard"))
check("Devanagari", string_utf8(G.string("उत्कर्ष"))[1].decode(), "उत्कर्ष")
check("a surrogate pair", string_utf8(G.string("key 🔑"))[1].decode(), "key 🔑")
check("an unpaired high surrogate", string_utf8(G.raw_string([0x41, 0xD800, 0x42]))[1], b"A\xef\xbf\xbdB")
check("an unpaired low surrogate", string_utf8(G.raw_string([0xDC00]))[1], b"\xef\xbf\xbd")
check("a high surrogate at the end", string_utf8(G.raw_string([0x41, 0xDBFF]))[1], b"A\xef\xbf\xbd")
check("NUL padding ends it", string_utf8(G.raw_string([0x41, 0, 0x42]))[1], b"A")
check("an odd length drops the half unit", string_utf8(b"\x05\x03A\x00B")[1], b"A")
check("NUL-terminated", string_utf8(G.string("abc"))[2], 0)
check("does not fit: whole characters only", string_utf8(G.string("ab€"), size=5)[:2], (2, b"ab"))
check("size 1: just the NUL", string_utf8(G.string("abc"), size=1)[:2], (0, b""))
check("size 0", _string(G.string("abc"), 8, None, 0), EDESC)
check("bLength past what was read", _string(G.string("abcdef"), 6, C.create_string_buffer(64), 64), EDESC)
check("not a string", string_utf8(b"\x04\x02A\x00")[0], EDESC)
check("empty", string_utf8(b"\x02\x03")[:2], (0, b""))

# ---- BOS -----------------------------------------------------------------------
uuid = bytes(range(16))
B = G.bos(G.cap_usb2(0x06), G.cap_ss(0, 0x0E, 1, 10, 2047), G.cap_container(uuid),
          G.cap_ssp([(0, 3, 0, 1, 10), (1, 3, 0x80 >> 6, 1, 10), (2, 2, 0, 1, 5000)]))
rc, b = bos_parse(B)
check("BOS: capabilities", (rc, b.caps, b.lpm, b.besl, b.ss, b.ss_speeds, b.ss_func, b.u1_lat, b.u2_lat),
      (0, 4, 1, 1, 1, 0x0E, 1, 10, 2047))
check("BOS: container and fastest sublink", (b.has_container, bytes(b.container), b.ssp, b.ssp_max_mbps),
      (1, uuid, 1, 10000))
rc, b = bos_parse(G.bos(G.cap_usb2(0x02)))
check("LPM without BESL", (rc, b.lpm, b.besl, b.ss), (0, 1, 0, 0))
rc, b = bos_parse(G.bos(G.cap_ssp([(0, 1, 0, 1, 50000)])))
check("a sublink given in Kbit/s", b.ssp_max_mbps, 50)
check("BOS truncated", bos_parse(B[:20])[0], ETRUNC)
check("SSP claiming more sublinks than it has", bos_parse(G.bos(G.cap_ssp([(0, 3, 0, 1, 10)])[:-4] +
                                                                b""))[0], EDESC)
check("a short SuperSpeed capability", bos_parse(G.bos(G.cap_ss()[:9]))[0], EDESC)
check("not a BOS", bos_parse(b"\x05\x02\x05\x00\x00")[0], EDESC)


# ---- fuzz: the reference parser ------------------------------------------------
def ref_config(data):
    n = len(data)
    if n < 9 or data[1] != 2 or data[0] < 9:
        return EDESC, None
    total = data[2] | data[3] << 8
    if total < data[0]:
        return EDESC, None
    if total > n:
        return ETRUNC, None
    ifaces, eps, iads = [], [], []
    warn = other = 0
    cur, last_ep, seen, high = -1, -1, set(), False
    off = data[0]
    while off < total:
        left = total - off
        if left < 2:
            return EDESC, None
        ln, kind = data[off], data[off + 1]
        if ln < 2 or ln > left:
            return EDESC, None
        d = data[off:off + ln]
        if kind == 4:
            if ln < 9:
                return EDESC, None
            if cur >= 0:
                ifaces[cur]["body_len"] = off - ifaces[cur]["body_off"]
            if len(ifaces) >= MAX_IFACES:
                return ETOOMANY, None
            cur = len(ifaces)
            ifaces.append(dict(number=d[2], alt=d[3], num_ep=d[4], cls=d[5], ep_count=0, first_ep=len(eps),
                               func=0xFF, hid=0, body_off=off + ln, body_len=0))
            if d[2] < 32:
                seen.add(d[2])
            else:
                high = True
            last_ep = -1
        elif kind == 5:
            if ln < 7:
                return EDESC, None
            if cur < 0:
                warn |= WARN_EP_ORPHAN
            else:
                if len(eps) >= MAX_EPS:
                    return ETOOMANY, None
                last_ep = len(eps)
                eps.append(dict(address=d[2], max_packet=d[4] | d[5] << 8, iface=cur, bpi=0))
                ifaces[cur]["ep_count"] += 1
        elif kind == 0x30:
            if ln < 6:
                return EDESC, None
            if last_ep >= 0:
                eps[last_ep]["bpi"] = d[4] | d[5] << 8
        elif kind == 0x31:
            if ln < 8:
                return EDESC, None
            if last_ep >= 0:
                eps[last_ep]["bpi"] = struct.unpack_from("<I", d, 4)[0]
        elif kind == 0x0B:
            if ln < 8:
                return EDESC, None
            if len(iads) >= MAX_IADS:
                warn |= WARN_IADS
            else:
                iads.append((d[2], d[3]))
        elif kind == 0x21:
            if ln < 6:
                return EDESC, None
            if cur >= 0:
                for j in range(d[5]):
                    if 9 + 3 * j > ln:
                        break
                    if d[6 + 3 * j] == 0x22 and ifaces[cur]["hid"] == 0:
                        ifaces[cur]["hid"] = d[7 + 3 * j] | d[8 + 3 * j] << 8
        else:
            other += 1
        off += ln
    if cur >= 0:
        ifaces[cur]["body_len"] = off - ifaces[cur]["body_off"]
    for i in ifaces:
        if i["num_ep"] != i["ep_count"]:
            warn |= WARN_EP_COUNT
        for k, (first, count) in enumerate(iads):
            if first <= i["number"] < first + count:
                i["func"] = k
                break
    if not high and len(seen) != data[4]:
        warn |= WARN_IFACES
    return 0, dict(ifaces=ifaces, eps=eps, niads=len(iads), warn=warn, other=other & 0xFF)


def mine(c):
    return dict(ifaces=[dict(number=i.number, alt=i.alt, num_ep=i.num_ep, cls=i.cls, ep_count=i.ep_count,
                             first_ep=i.first_ep, func=i.func, hid=i.hid_report_len, body_off=i.body_off,
                             body_len=i.body_len) for i in c.ifaces[:c.iface_count]],
                eps=[dict(address=e.address, max_packet=e.max_packet, iface=e.iface, bpi=e.ss_bpi)
                     for e in c.eps[:c.ep_count]],
                niads=c.iad_count, warn=c.warn, other=c.other)


def ref_string(d):
    if len(d) < 2 or d[0] < 2 or d[0] > len(d) or d[1] != 3:
        return EDESC, None
    units = [d[2 + 2 * k] | d[3 + 2 * k] << 8 for k in range((d[0] - 2) // 2)]
    out, k = "", 0
    while k < len(units):
        u = units[k]
        k += 1
        if u == 0:
            break
        if 0xDC00 <= u < 0xE000:
            u = 0xFFFD
        elif 0xD800 <= u < 0xDC00:
            if k < len(units) and 0xDC00 <= units[k] < 0xE000:
                u = 0x10000 + ((u - 0xD800) << 10) + (units[k] - 0xDC00)
                k += 1
            else:
                u = 0xFFFD
        out += chr(u)
    out = out.encode("utf-8")
    return len(out), out


rng = random.Random(0x55B)
seeds = [G.KEYBOARD_CONFIG, AUDIO, SS]
kinds = [2, 4, 5, 0x0B, 0x21, 0x24, 0x25, 0x30, 0x31, 0xFF]
mismatches = 0
for r in range(ROUNDS):
    mode = r % 4
    if mode == 0:                                       # mutate a real one
        d = bytearray(rng.choice(seeds))
        for _ in range(rng.randint(1, 6)):
            p = rng.randrange(len(d))
            d[p] = rng.choice([0, 1, 2, 6, 7, 8, 9, 0x22, 0xFF, rng.randrange(256)])
    elif mode == 1:                                     # descriptors of random kinds and sizes
        parts = []
        for _ in range(rng.randint(0, 40)):
            ln = rng.choice([0, 1, 2, 5, 6, 7, 8, 9, 10, rng.randrange(256)])
            body = bytes(rng.randrange(256) for _ in range(max(ln - 2, 0)))
            parts.append(bytes([ln, rng.choice(kinds)]) + body)
        d = bytearray(G.config(*parts))
    elif mode == 2:                                     # truncation and lengths
        d = bytearray(rng.choice(seeds))
        if rng.random() < 0.5:
            struct.pack_into("<H", d, 2, rng.randrange(0x10000))
        d = d[:rng.randrange(len(d) + 1)]
    else:                                               # pure noise
        d = bytearray(rng.randrange(256) for _ in range(rng.randrange(80)))
        if len(d) >= 2 and rng.random() < 0.8:
            d[1] = 2
    rc, c = config_parse(bytes(d))
    want_rc, want = ref_config(bytes(d))
    got = mine(c) if rc == 0 else None
    if (rc, got) != (want_rc, want):
        mismatches += 1
        if mismatches <= 3:
            print("FAIL fuzz config", d.hex(), rc, want_rc)
            print("  got ", got)
            print("  want", want)
    # strings: mutate and compare
    s = bytearray(G.string(rng.choice(["abc", "उत्कर्ष", "🔑x", ""])) + bytes(rng.randrange(256) for _ in range(8)))
    for _ in range(rng.randint(0, 3)):
        s[rng.randrange(len(s))] = rng.choice([0x00, 0xD8, 0xDC, 0xDB, 0xDF, 0x03, rng.randrange(256)])
    s = bytes(s[:rng.randrange(len(s) + 1)])
    rc, out, _ = string_utf8(s, size=256)
    want_rc, want = ref_string(s)
    if (rc, out) != (want_rc, want):
        mismatches += 1
        if mismatches <= 3:
            print("FAIL fuzz string", s.hex(), rc, out, want_rc, want)
    if r % 8 == 0:                                      # BOS: no crash, no stray writes
        bd = bytearray(B)
        for _ in range(rng.randint(1, 5)):
            bd[rng.randrange(len(bd))] = rng.randrange(256)
        bos_parse(bytes(bd[:rng.randrange(len(bd) + 1)]))
check(f"fuzz: {ROUNDS} rounds agree with the reference, nothing written outside", mismatches, 0)

print(f"test_desc: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

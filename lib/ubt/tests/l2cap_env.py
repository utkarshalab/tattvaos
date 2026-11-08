"""What the L2CAP tests share: the library's records as ctypes structures,
memory and a clock for the stack, two adapters on the virtual radio with a
BR/EDR link between them, channel users that record what they get, and
helpers to read and inject frames."""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import radio as R  # noqa: E402

UP, DOWN, FAILED = 1, 2, 3
EV_OPEN, EV_CLOSED, EV_REFUSED = 1, 2, 3
WHY_TIMEOUT, WHY_LINK, WHY_PEER, WHY_MODE = 0x1000, 0x1001, 0x1002, 0x1003
BASIC, ERTM, STREAMING, LE_CREDITS, ECRED = 0x00, 0x03, 0x04, 0x80, 0x81
EV_RECONF = 4


class Conn(C.Structure):
    _fields_ = [("adapter", C.c_uint64), ("handle", C.c_uint16), ("type", C.c_uint8), ("role", C.c_uint8),
                ("peer", C.c_uint8 * 6), ("peer_type", C.c_uint8), ("state", C.c_uint8), ("pad0", C.c_uint32),
                ("tx_head", C.c_uint64), ("tx_tail", C.c_uint64), ("in_flight", C.c_uint32),
                ("rx_len", C.c_uint32), ("rx_need", C.c_uint32), ("ident", C.c_uint8), ("info_state", C.c_uint8),
                ("info_ident", C.c_uint8), ("pad", C.c_uint8), ("ext_features", C.c_uint32), ("pad2", C.c_uint32),
                ("fixed_chans", C.c_uint64), ("rx_buf", C.c_uint64), ("user", C.c_uint64)]


class Chan(C.Structure):
    _fields_ = [("conn", C.c_uint64), ("ops", C.c_uint64), ("user", C.c_uint64), ("deadline", C.c_uint64),
                ("scid", C.c_uint16), ("dcid", C.c_uint16), ("psm", C.c_uint16), ("imtu", C.c_uint16),
                ("omtu", C.c_uint16), ("state", C.c_uint8), ("mode", C.c_uint8), ("ident", C.c_uint8),
                ("cfg", C.c_uint8), ("outgoing", C.c_uint8), ("pad", C.c_uint8),
                ("peer_txwin", C.c_uint8), ("peer_maxtx", C.c_uint8), ("peer_mps", C.c_uint16),
                ("retrans_ms", C.c_uint16), ("monitor_ms", C.c_uint16), ("cred", C.c_uint64), ("ertm", C.c_uint64)]


class Ertm(C.Structure):
    _fields_ = [(n, C.c_uint32) for n in ("txwin", "maxtx", "mps", "retrans_ms", "monitor_ms", "next_tx", "exp_ack",
                                          "exp_tx", "unacked", "retry", "flags", "pad")] + [
        ("retrans_at", C.c_uint64), ("monitor_at", C.c_uint64), ("txq", C.c_uint64), ("txq_tail", C.c_uint64),
        ("sent", C.c_uint64 * 64), ("sdu", C.c_uint64), ("sdu_len", C.c_uint32), ("sdu_got", C.c_uint32),
        ("sdu_on", C.c_uint32), ("pad2", C.c_uint32)]


class Cred(C.Structure):
    _fields_ = [(n, C.c_uint32) for n in ("tx_credits", "rx_credits", "mps", "new_mtu", "index", "pad")] + [
        ("leader", C.c_uint64), ("txq", C.c_uint64), ("txq_tail", C.c_uint64), ("sdu", C.c_uint64),
        ("sdu_size", C.c_uint32), ("sdu_len", C.c_uint32), ("sdu_got", C.c_uint32), ("pad2", C.c_uint32)]


class Ops(C.Structure):
    _fields_ = [("recv", C.c_void_p), ("event", C.c_void_p)]


def crc16(data, crc=0):
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


class Side:
    def __init__(self, name):
        self.name = name
        self.links, self.events, self.data = [], [], []
        self.conn_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_void_p)(
            lambda a, ev, c: self.links.append((ev, c)))
        self.recv_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(
            lambda ch, p, n: self.data.append((ch, C.string_at(p, n))))
        self.event_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_uint32, C.c_uint32)(
            lambda ch, ev, why: self.events.append((ch, ev, why)))
        self.ops = Ops(C.cast(self.recv_cb, C.c_void_p).value, C.cast(self.event_cb, C.c_void_p).value)

    def conn(self):
        ups = [c for ev, c in self.links if ev == UP]
        return ups[-1] if ups else None


class Env:
    def __init__(self, so):
        self.lib = lib = C.CDLL(so)
        self.arena = C.create_string_buffer(32 << 20)
        self.next = C.addressof(self.arena)
        self.live = {}
        self.now = [1000]
        self.hooks = [C.CFUNCTYPE(C.c_uint64, C.c_uint64, C.c_uint64)(self._alloc),
                      C.CFUNCTYPE(None, C.c_uint64, C.c_uint64, C.c_uint64)(self._free),
                      C.CFUNCTYPE(None, C.c_uint64)(lambda us: None),
                      C.CFUNCTYPE(C.c_uint64)(lambda: self.now[0])]
        for name, cb in zip(("usb_alloc_fn", "usb_free_fn", "usb_delay_fn", "ubt_clock_fn"), self.hooks):
            C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value
        self.fn = lambda n, res, *a: self._fn(n, res, *a)
        self.connect = self.fn("ubt_connect", C.c_int32, C.c_void_p, C.c_char_p)
        self.disconnect = self.fn("ubt_disconnect", None, C.c_void_p, C.c_uint32)
        self.server = self.fn("l2cap_server", C.c_int32, C.c_uint32, C.c_uint32, C.c_void_p, C.c_void_p)
        self.l2connect = self.fn("l2cap_connect", C.c_void_p, C.c_void_p, C.c_uint32, C.c_uint32, C.c_void_p,
                                 C.c_void_p)
        self.l2send = self.fn("l2cap_send", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
        self.l2disconnect = self.fn("l2cap_disconnect", None, C.c_void_p)
        self.le_connect = self.fn("ubt_le_connect", C.c_int32, C.c_void_p, C.c_char_p, C.c_uint32)
        self.connect_ecred = self.fn("l2cap_connect_ecred", C.c_uint32, C.c_void_p, C.c_uint32, C.c_uint32,
                                     C.c_void_p, C.c_void_p, C.c_void_p)
        self.reconfigure = self.fn("l2cap_reconfigure", C.c_int32, C.c_void_p, C.c_uint32)
        self.service = self.fn("ubt_service", None)
        self.remove = self.fn("ubt_mem_remove", None, C.c_void_p)
        self.radio = R.Radio(lib)
        self.A_ADDR, self.B_ADDR = bytes([0xAA] * 6), bytes([0xBB, 1, 2, 3, 4, 5])
        self.a, self.ca = self.radio.add(self.A_ADDR)
        self.b, self.cb = self.radio.add(self.B_ADDR)
        self.SA, self.SB = Side("A"), Side("B")
        acl_fn = list((C.c_uint32 * 30).in_dll(lib, "ubt_layout"))[26]
        for adapter, side in ((self.a, self.SA), (self.b, self.SB)):
            C.c_void_p.from_address(adapter + acl_fn + 8).value = C.cast(side.conn_cb, C.c_void_p).value
        self.passed = self.failed = 0

    def _fn(self, n, res, *args):
        f = getattr(self.lib, n)
        f.restype = res
        f.argtypes = list(args)
        return f

    def _alloc(self, size, align):
        p = (self.next + align - 1) & ~(align - 1)
        self.next = p + size
        self.live[p] = size
        return p

    def _free(self, p, size, align):
        assert self.live.pop(p) == size, "freed with another size"

    def settle(self, rounds=8):
        for _ in range(rounds):
            self.radio.run()
            self.service()
        self.radio.run()

    def link(self):
        self.connect(self.a, self.B_ADDR)
        self.settle()
        return self.SA.conn(), self.SB.conn()

    def le_link(self):
        self.SA.links.clear()
        self.SB.links.clear()
        self.le_connect(self.a, self.B_ADDR, 0)
        self.settle()
        return self.SA.conn(), self.SB.conn()

    def check(self, label, got, want):
        if got == want:
            self.passed += 1
        else:
            self.failed += 1
            print(f"FAIL {label}: got {got!r}, want {want!r}")

    def frames(self, ctrl, start=0):
        """The L2CAP frames a controller's host sent, put back together."""
        out, cur = [], b""
        for h, pb, data in ctrl.sent[start:]:
            cur = data if pb in (0, 2) else cur + data
            if len(cur) >= 4 and len(cur) == struct.unpack_from("<H", cur)[0] + 4:
                out.append(cur)
                cur = b""
        return out

    def on_cid(self, ctrl, cid, start=0):
        return [f for f in self.frames(ctrl, start) if struct.unpack_from("<H", f, 2)[0] == cid]

    def sig(self, ctrl, start=0, cid=1):
        out = []
        for f in self.on_cid(ctrl, cid, start):
            p = f[4:]
            while len(p) >= 4:
                code, ident, n = struct.unpack_from("<BBH", p)
                out.append((code, ident, p[4:4 + n]))
                p = p[4 + n:]
        return out

    def inject(self, ctrl, handle, frame):
        self.radio.inject(ctrl, handle, 2, frame)
        self.settle()


def ertm_frame(cid, control, payload=b"", fcs=True):
    body = struct.pack("<H", control) + payload
    head = struct.pack("<HH", len(body) + 2, cid)
    c = crc16(head + body)
    return head + body + struct.pack("<H", c if fcs else c ^ 0xFFFF)


def iframe(cid, txseq, reqseq, sar=0, payload=b"", f=0, fcs=True):
    return ertm_frame(cid, (txseq << 1) | (f << 7) | (reqseq << 8) | (sar << 14), payload, fcs)


def sframe(cid, kind, reqseq, p=0, f=0):
    return ertm_frame(cid, 1 | (kind << 2) | (p << 4) | (f << 7) | (reqseq << 8))


def parse(frame):
    """An ERTM frame → (cid, control fields, payload, FCS good)."""
    n, cid, control = struct.unpack_from("<HHH", frame)
    good = crc16(frame[:-2]) == struct.unpack_from("<H", frame, len(frame) - 2)[0]
    if control & 1:
        return cid, {"s": (control >> 2) & 3, "p": (control >> 4) & 1, "f": (control >> 7) & 1,
                     "req": (control >> 8) & 63}, b"", good
    return cid, {"tx": (control >> 1) & 63, "f": (control >> 7) & 1, "req": (control >> 8) & 63,
                 "sar": control >> 14}, frame[6:-2], good

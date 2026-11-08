"""A Bluetooth controller on USB, for the lib/ubt host tests: a standard
HCI device (class E0/01/01) on the simulated xHCI controller of lib/usb.

Commands arrive as class control requests; events go out on the interrupt
endpoint in packets of its size; ACL data goes both ways on the bulk pair
(with an echo mode that sends packets back in pieces).
"""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "usb", "sim"))
import devices as D  # noqa: E402

G = D.G
EV_CMD_COMPLETE, EV_CMD_STATUS, EV_HW_ERROR = 0x0E, 0x0F, 0x10


class HciController(D.Device):
    def __init__(self, vid=0x1915, pid=0x521F, le=True, ev_mps=16, hci_version=0x0B, manufacturer=0x0059,
                 address=bytes([0x11, 0x22, 0x33, 0x44, 0x55, 0x66])):
        cfg = G.config(
            G.interface(0, num_ep=3, cls=0xE0, sub=1, proto=1),
            G.endpoint(0x81, 3, ev_mps, 1), G.endpoint(0x82, 2, 64, 0), G.endpoint(0x02, 2, 64, 0),
            G.interface(1, num_ep=2, cls=0xE0, sub=1, proto=1),
            G.endpoint(0x83, 1, 0, 1), G.endpoint(0x03, 1, 0, 1),
            G.interface(1, alt=1, num_ep=2, cls=0xE0, sub=1, proto=1),
            G.endpoint(0x83, 1, 9, 1), G.endpoint(0x03, 1, 9, 1))
        D.Device.__init__(self, G.device(vid=vid, pid=pid, cls=0xE0, sub=1, proto=1, mps0=64,
                                         manufacturer=1, product=2, serial=0),
                          cfg, {1: "Nordic", 2: "HCI USB"}, speed=D.SPEED_FULL)
        self.ev_mps = ev_mps
        self.le = le
        self.hci_version = hci_version
        self.manufacturer = manufacturer
        self.address = address
        self.commands = []          # opcodes received
        self.params = {}            # opcode → its parameters (answered ones)
        self.refuse = {}            # opcode → HCI status to answer with
        self.ignore = set()         # opcodes never answered
        self.with_status = set()    # answered with Command Status
        self.acl_out = []
        self.echo = False
        self.echo_pieces = 1

    def event(self, code, params):
        ev = bytes([code, len(params)]) + params
        for i in range(0, len(ev), self.ev_mps):
            self.queue(0x81, ev[i:i + self.ev_mps])
        if len(ev) % self.ev_mps == 0:
            self.queue(0x81, b"")           # a zero-length packet ends it

    def complete(self, opcode, ret):
        self.event(EV_CMD_COMPLETE, bytes([1]) + struct.pack("<H", opcode) + ret)

    def hci(self, cmd):
        opcode, plen = struct.unpack_from("<HB", cmd)
        params = cmd[3:3 + plen]
        self.commands.append(opcode)
        if opcode in self.ignore:
            return
        if opcode in self.refuse:
            self.complete(opcode, bytes([self.refuse[opcode]]))
            return
        if opcode in self.with_status:
            self.event(EV_CMD_STATUS, bytes([0, 1]) + struct.pack("<H", opcode))
            return
        features = bytearray(8)
        features[0] = 0xFF
        if self.le:
            features[4] |= 1 << 6
        ret = {
            0x0C03: b"",
            0x1001: struct.pack("<BHBHH", self.hci_version, 0x1234, self.hci_version, self.manufacturer, 0x5678),
            0x1002: bytes(range(64)),
            0x1003: bytes(features),
            0x1005: struct.pack("<HBHH", 1021, 64, 8, 16),
            0x1009: self.address,
            0x0C01: b"",
            0x2001: b"",
            0x2002: struct.pack("<HB", 251, 15),
        }.get(opcode)
        if ret is None:
            self.complete(opcode, bytes([0x01]))    # Unknown HCI Command
            return
        self.params[opcode] = params
        self.complete(opcode, bytes([0]) + ret)

    def control(self, setup, out):
        rt, req, value, index, length = struct.unpack("<BBHHH", setup)
        if rt == 0x20 and req == 0 and out is not None:
            self.requests.append((rt, req, value, index, length))
            self.hci(bytes(out))
            return b""
        return D.Device.control(self, setup, out)

    def write(self, address, data):
        self.acl_out.append((address, data))
        if self.echo and address == 0x02:
            n = max(1, len(data) // self.echo_pieces)
            for i in range(0, len(data), n):
                self.queue(0x82, data[i:i + n])

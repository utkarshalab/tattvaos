"""A virtual radio for the lib/ubt host tests: controllers for adapters on
the in-memory transport (tr/mem.asm), linking them to each other.

Each controller answers the bring-up commands (with small buffers, so
fragmentation and flow control get used), makes BR/EDR links (paging and
the far side's Connection Request and acceptance) and LE links, ends them,
applies LE connection updates, and carries ACL packets between the two
ends of a link, giving the sender its Number of Completed Packets back.

Nothing is delivered from inside a call into the stack: every event and
packet goes on a queue that run() empties, so the two stacks never call
into each other half-way through something.
"""
import ctypes as C
import struct

EV_CONN_COMPLETE, EV_CONN_REQUEST, EV_DISCONNECT = 0x03, 0x04, 0x05
EV_CMD_COMPLETE, EV_CMD_STATUS, EV_NUM_COMPLETED, EV_LE_META = 0x0E, 0x0F, 0x13, 0x3E


class Controller:
    def __init__(self, radio, adapter, address, acl_mtu, acl_count, le_mtu, le_count, le=True):
        self.radio, self.adapter, self.address = radio, adapter, bytes(address)
        self.acl_mtu, self.acl_count, self.le_mtu, self.le_count, self.le = acl_mtu, acl_count, le_mtu, le_count, le
        self.commands = []
        self.next_handle = 0x0040
        self.links = {}             # our handle → (peer controller, its handle, kind)
        self.sent = []              # ACL packets this side sent (handle-stripped)
        self.hold_completed = False
        self.held = 0
        self.deaf = False           # drop what comes to us over the air
        self.accept = True          # accept incoming BR/EDR links
        self.updates = []
        # GAP: what this controller advertises, scans for, answers inquiries with
        self.adv_type, self.adv_data, self.scan_rsp, self.advertising = 0, b"", b"", False
        self.scanning, self.active, self.no_dups, self.seen = False, False, False, set()
        self.scan_enable, self.inquiry_mode, self.cls, self.name, self.eir = 0, 0, 0, b"", bytes(240)
        self.rssi = -50

    def event(self, code, params):
        self.radio.queue.append(("event", self, bytes([code, len(params)]) + bytes(params)))

    def complete(self, opcode, ret):
        self.event(EV_CMD_COMPLETE, bytes([1]) + struct.pack("<H", opcode) + ret)

    def status(self, opcode, st=0):
        self.event(EV_CMD_STATUS, bytes([st, 1]) + struct.pack("<H", opcode))

    def new_handle(self):
        h = self.next_handle
        self.next_handle += 1
        return h

    def command(self, cmd):
        opcode, plen = struct.unpack_from("<HB", cmd)
        p = cmd[3:3 + plen]
        self.commands.append(opcode)
        features = bytearray(8)
        features[0] = 0xFF
        if self.le:
            features[4] |= 1 << 6
        simple = {
            0x0C03: b"",
            0x1001: struct.pack("<BHBHH", 0x0B, 1, 0x0B, 0x0002, 1),
            0x1002: bytes(64),
            0x1003: bytes(features),
            0x1005: struct.pack("<HBHH", self.acl_mtu, 64, self.acl_count, 8),
            0x1009: self.address,
            0x0C01: b"",
            0x2001: b"",
            0x2002: struct.pack("<HB", self.le_mtu, self.le_count),
        }
        if opcode in simple:
            self.complete(opcode, bytes([0]) + simple[opcode])
            return
        if self.gap_command(opcode, p):
            return
        if opcode == 0x0405:                            # Create Connection
            self.status(opcode)
            peer = self.radio.by_address(p[:6])
            if peer is None or not peer.accept:
                self.event(EV_CONN_COMPLETE, bytes([0x04]) + struct.pack("<H", 0) + p[:6] + b"\x01\x00")
                return
            self.radio.paging[(peer, self.address)] = self
            peer.event(EV_CONN_REQUEST, self.address + b"\x00\x00\x00\x01")
            return
        if opcode == 0x0409:                            # Accept Connection Request
            self.status(opcode)
            caller = self.radio.paging.pop((self, bytes(p[:6])), None)
            if caller is None:
                return
            h1, h2 = caller.new_handle(), self.new_handle()
            caller.links[h1] = (self, h2, "br")
            self.links[h2] = (caller, h1, "br")
            caller.event(EV_CONN_COMPLETE, bytes([0]) + struct.pack("<H", h1) + self.address + b"\x01\x00")
            self.event(EV_CONN_COMPLETE, bytes([0]) + struct.pack("<H", h2) + caller.address + b"\x01\x00")
            return
        if opcode == 0x200D:                            # LE Create Connection
            self.status(opcode)
            peer = self.radio.by_address(p[6:12])
            if peer is None:
                return                                  # nobody advertising: it just waits
            h1, h2 = self.new_handle(), peer.new_handle()
            self.links[h1] = (peer, h2, "le")
            peer.links[h2] = (self, h1, "le")
            for c, h, role, other in ((self, h1, 0, peer), (peer, h2, 1, self)):
                c.event(EV_LE_META, bytes([0x01, 0]) + struct.pack("<HBB", h, role, 0) + other.address
                        + struct.pack("<HHHB", 24, 0, 500, 0))
            return
        if opcode == 0x0406:                            # Disconnect
            self.status(opcode)
            h, reason = struct.unpack_from("<HB", p)
            link = self.links.pop(h, None)
            if link is None:
                return
            peer, ph, _ = link
            peer.links.pop(ph, None)
            self.event(EV_DISCONNECT, bytes([0]) + struct.pack("<HB", h, 0x16))
            peer.event(EV_DISCONNECT, bytes([0]) + struct.pack("<HB", ph, reason))
            return
        if opcode == 0x2013:                            # LE Connection Update
            self.status(opcode)
            self.updates.append(bytes(p))
            return
        self.complete(opcode, bytes([0x01]))           # Unknown HCI Command

    def gap_command(self, opcode, p):
        """Advertising, scanning, inquiry and names → True when handled."""
        ok = lambda: self.complete(opcode, b"\x00")
        if opcode == 0x2006:                            # LE Set Advertising Parameters
            self.adv_type = p[4]
        elif opcode == 0x2008:                          # LE Set Advertising Data
            self.adv_data = bytes(p[1:1 + p[0]])
        elif opcode == 0x2009:                          # LE Set Scan Response Data
            self.scan_rsp = bytes(p[1:1 + p[0]])
        elif opcode == 0x200A:                          # LE Set Advertising Enable
            self.advertising = bool(p[0])
            ok()
            if self.advertising:
                for c in self.radio.controllers.values():
                    if c is not self and c.scanning:
                        c.hear(self)
            return True
        elif opcode == 0x200B:                          # LE Set Scan Parameters
            self.active = bool(p[0])
        elif opcode == 0x200C:                          # LE Set Scan Enable
            self.scanning, self.no_dups, self.seen = bool(p[0]), bool(p[1]), set()
            ok()
            if self.scanning:
                for c in self.radio.controllers.values():
                    if c is not self and c.advertising:
                        self.hear(c)
            return True
        elif opcode == 0x0C13:                          # Write Local Name
            self.name = bytes(p).split(b"\x00")[0]
        elif opcode == 0x0C1A:                          # Write Scan Enable
            self.scan_enable = p[0]
        elif opcode == 0x0C24:                          # Write Class of Device
            self.cls = int.from_bytes(p[:3], "little")
        elif opcode == 0x0C45:                          # Write Inquiry Mode
            self.inquiry_mode = p[0]
        elif opcode == 0x0C52:                          # Write Extended Inquiry Response
            self.eir = bytes(p[1:241])
        elif opcode in (0x0C56, 0x0C7A, 0x0402):        # SSP mode, SC support, Inquiry Cancel
            pass
        elif opcode == 0x0401:                          # Inquiry
            self.status(opcode)
            found = [c for c in self.radio.controllers.values() if c is not self and c.scan_enable & 1]
            if p[4]:
                found = found[:p[4]]
            for c in found:
                rec = c.address + bytes([1])
                if self.inquiry_mode == 0:
                    self.event(0x02, bytes([1]) + rec + b"\x00\x00" + c.cls.to_bytes(3, "little") + b"\x00\x00")
                elif self.inquiry_mode == 1:
                    self.event(0x22, bytes([1]) + rec + b"\x00" + c.cls.to_bytes(3, "little") + b"\x00\x00"
                               + struct.pack("<b", c.rssi))
                else:
                    self.event(0x2F, bytes([1]) + rec + b"\x00" + c.cls.to_bytes(3, "little") + b"\x00\x00"
                               + struct.pack("<b", c.rssi) + c.eir)
            self.event(0x01, b"\x00")
            return True
        elif opcode == 0x0419:                          # Remote Name Request
            self.status(opcode)
            peer = self.radio.by_address(p[:6])
            if peer is None or not peer.scan_enable & 2:
                self.event(0x07, b"\x04" + bytes(p[:6]) + bytes(248))
            else:
                self.event(0x07, b"\x00" + bytes(p[:6]) + peer.name.ljust(248, b"\x00"))
            return True
        else:
            return False
        ok()
        return True

    def hear(self, adv):
        """This scanning controller hears an advertiser: its reports."""
        kinds = [(adv.adv_type, adv.adv_data)]
        if self.active and adv.adv_type in (0, 2):
            kinds.append((4, adv.scan_rsp))
        for t, data in kinds:
            if self.no_dups and (adv.address, t) in self.seen:
                continue
            self.seen.add((adv.address, t))
            self.event(EV_LE_META, bytes([0x02, 1, t, 0]) + adv.address + bytes([len(data)]) + data
                       + struct.pack("<b", adv.rssi))

    def acl(self, pkt):
        word, length = struct.unpack_from("<HH", pkt)
        h, flags = word & 0x0FFF, word & 0xF000
        self.sent.append((h, flags >> 12, bytes(pkt[4:4 + length])))
        link = self.links.get(h)
        if link is not None:
            peer, ph, _ = link
            if not peer.deaf:
                self.radio.queue.append(("acl", peer, struct.pack("<HH", ph | flags, length) + bytes(pkt[4:4 + length])))
        if self.hold_completed:
            self.held += 1
        else:
            self.event(EV_NUM_COMPLETED, struct.pack("<BHH", 1, h, 1))

    def release(self):
        """The packets held back come out as completed now."""
        n, self.held, self.hold_completed = self.held, 0, False
        for h in list(self.links) or [0]:
            if n:
                self.event(EV_NUM_COMPLETED, struct.pack("<BHH", 1, h, n))
                n = 0


class Radio:
    def __init__(self, lib):
        self.lib = lib
        self.controllers = {}       # adapter address → Controller
        self.queue = []
        self.paging = {}
        self.cmd_cb = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p, C.c_uint32)(
            lambda a, p, n: self.controllers[a].command(C.string_at(p, n)))
        self.acl_cb = C.CFUNCTYPE(C.c_int32, C.c_void_p, C.c_void_p, C.c_uint32)(self._acl)
        self.poll_cb = C.CFUNCTYPE(None, C.c_void_p)(lambda a: self.run())
        for name, cb in (("ubt_mem_cmd_fn", self.cmd_cb), ("ubt_mem_acl_fn", self.acl_cb),
                         ("ubt_mem_poll_fn", self.poll_cb)):
            C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value
        self.busy = set()           # controllers refusing ACL for now
        self.event_fn = self.lib.ubt_hci_event
        self.event_fn.argtypes = [C.c_void_p, C.c_char_p, C.c_uint32]
        self.acl_fn = self.lib.ubt_acl_input
        self.acl_fn.argtypes = [C.c_void_p, C.c_char_p, C.c_uint32]
        self.running = False

    def _acl(self, a, p, n):
        c = self.controllers[a]
        if c in self.busy:
            return -3
        c.acl(C.string_at(p, n))
        return 0

    def add(self, address, acl_mtu=27, acl_count=3, le_mtu=27, le_count=2, le=True):
        new = self.lib.ubt_mem_adapter
        new.restype = C.c_void_p
        new.argtypes = [C.c_void_p]
        a = new(None)
        c = Controller(self, a, address, acl_mtu, acl_count, le_mtu, le_count, le)
        self.controllers[a] = c
        init = self.lib.ubt_hci_init
        init.argtypes = [C.c_void_p]
        assert init(a) == 0, "bring-up"
        return a, c

    def by_address(self, address):
        for c in self.controllers.values():
            if c.address == bytes(address):
                return c
        return None

    def inject_event(self, ctrl, code, params):
        """An event to a controller's host as if the controller sent it."""
        ctrl.event(code, params)

    def inject(self, ctrl, handle, flags, data):
        """An ACL packet to a controller's host as if from the air."""
        self.queue.append(("acl", ctrl, struct.pack("<HH", handle | (flags << 12), len(data)) + bytes(data)))

    def run(self, limit=100000):
        if self.running:
            return                  # already emptying the queue further up
        self.running = True
        try:
            n = 0
            while self.queue and n < limit:
                kind, c, data = self.queue.pop(0)
                n += 1
                if kind == "event":
                    self.event_fn(c.adapter, data, len(data))
                else:
                    self.acl_fn(c.adapter, data, len(data))
        finally:
            self.running = False

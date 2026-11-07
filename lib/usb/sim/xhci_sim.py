"""A software xHCI controller for the lib/usb host tests.

The driver's register accesses arrive through the usb_rd32/usb_wr32 hooks;
rings, contexts and buffers are the driver's own memory, read and written
here through ctypes. Everything happens when it is written: a doorbell runs
the ring at once, so a test is deterministic.

Covers what the driver uses so far: capability, operational and runtime
registers, firmware hand-off (USB legacy support), supported protocol
capabilities, the command ring (Enable/Disable Slot, Address Device,
Evaluate Context, Configure Endpoint, Reset Endpoint, Set TR Dequeue, No-op),
EP0 control transfers, the event ring with its segment table, and root
ports (connect, reset, warm reset, speed, change bits).
"""
import ctypes as C
import struct

CAPLENGTH, RTSOFF, DBOFF, XECP = 0x20, 0x2000, 0x3000, 0x8000
OP = CAPLENGTH
PORT_CCS, PORT_PED, PORT_PR, PORT_PP = 1, 2, 1 << 4, 1 << 9
PORT_CSC, PORT_PEC, PORT_WRC, PORT_OCC, PORT_PRC, PORT_PLC, PORT_CEC = (1 << b for b in range(17, 24))
PORT_WPR = 1 << 31
CHANGES = PORT_CSC | PORT_PEC | PORT_WRC | PORT_OCC | PORT_PRC | PORT_PLC | PORT_CEC
CC_SUCCESS, CC_TRANSACTION, CC_TRB, CC_STALL, CC_NO_SLOTS, CC_SHORT, CC_CTX_STATE = 1, 4, 5, 6, 9, 13, 19
EP_DISABLED, EP_RUNNING, EP_HALTED, EP_STOPPED = 0, 1, 2, 3


def rd(addr, n):
    return C.string_at(addr, n)


def wr(addr, data):
    C.memmove(addr, bytes(data), len(data))


def u32(addr):
    return struct.unpack("<I", rd(addr, 4))[0]


def u64(addr):
    return struct.unpack("<Q", rd(addr, 8))[0]


class Port:
    def __init__(self, major):
        self.major = major
        self.dev = None
        self.ccs = self.ped = 0
        self.changes = 0
        self.speed = 0
        self.resets = 0
        self.warm_resets = 0


class Endpoint:
    def __init__(self, deq, dcs, mps, kind):
        self.deq, self.ccs, self.mps, self.kind = deq, dcs, mps, kind
        self.state = EP_RUNNING


class Slot:
    def __init__(self, sid):
        self.sid = sid
        self.port = 0
        self.dev = None
        self.address = 0
        self.eps = {}


class XhciSim:
    def __init__(self, usb2_ports=2, usb3_ports=2, max_slots=32, csz=False, scratchpads=2, ac64=True,
                 bios_owned=True, stubborn_bios=False, cnr_reads=3, reset_sticks=False):
        self.mmio = C.create_string_buffer(0x10000)
        self.base = C.addressof(self.mmio)
        self.ports = [Port(2) for _ in range(usb2_ports)] + [Port(3) for _ in range(usb3_ports)]
        self.usb2_ports, self.usb3_ports = usb2_ports, usb3_ports
        self.max_slots, self.csz, self.ctx = max_slots, csz, 64 if csz else 32
        self.scratchpads, self.ac64 = scratchpads, ac64
        self.legsup = (1 << 16) if bios_owned else 0
        self.legctl = 0x0000E011 | 0xE0000000       # SMIs on, latched events
        self.stubborn = stubborn_bios
        self.cnr_reads_after_reset = cnr_reads
        self.reset_sticks = reset_sticks
        self.log = []                                # (kind, ...) of interest to tests
        self.stall_next_doorbell = False
        self.deaf = False                            # ignore transfer doorbells
        self._power_on()

    # ---- state -------------------------------------------------------------------
    def _power_on(self):
        self.usbcmd = 0
        self.usbsts = 1                              # HCH
        self.cnr_left = 0
        self.hcrst_left = 0
        self.regs = {}                               # plain registers by offset
        self.config = 0
        self.crcr_lo = self.crcr_hi = 0
        self.cmd_deq, self.cmd_ccs = 0, 1
        self.erst = None                             # (segment base, size)
        self.evt_enq, self.evt_pcs = 0, 1
        self.iman = 0
        self.slots = {}
        self.events_posted = 0
        self.ring_full = 0

    def attach(self, port_no, dev):
        p = self.ports[port_no - 1]
        p.dev, p.ccs = dev, 1
        p.changes |= PORT_CSC
        if p.major == 3 and dev.speed >= 4:
            if not getattr(dev, "untrained", False):
                p.ped, p.speed = 1, dev.speed        # a USB 3 link trains by itself
        self._port_event(port_no)

    def detach(self, port_no):
        p = self.ports[port_no - 1]
        p.dev, p.ccs, p.ped, p.speed = None, 0, 0, 0
        p.changes |= PORT_CSC | PORT_PEC
        self._port_event(port_no)

    def _running(self):
        return not (self.usbsts & 1)

    # ---- register access -------------------------------------------------------
    def read(self, addr):
        off = addr - self.base
        if off == 0:
            return CAPLENGTH | (0x0120 << 16)
        if off == 0x04:
            return self.max_slots | (8 << 8) | (len(self.ports) << 24)
        if off == 0x08:
            hi, lo = self.scratchpads >> 5, self.scratchpads & 31
            return (1 << 4) | (hi << 21) | (lo << 27)
        if off == 0x10:
            return (1 if self.ac64 else 0) | (4 if self.csz else 0) | ((XECP // 4) << 16)
        if off == 0x14:
            return DBOFF
        if off == 0x18:
            return RTSOFF
        if off == OP:                                # USBCMD
            if self.hcrst_left:
                self.hcrst_left -= 1
                if self.hcrst_left == 0 and not self.reset_sticks:
                    self.usbcmd &= ~2
            return self.usbcmd
        if off == OP + 4:                            # USBSTS
            v = self.usbsts
            if self.cnr_left:
                self.cnr_left -= 1
                v |= 1 << 11
            return v
        if off == OP + 8:
            return 1                                 # 4 KB pages
        if off == OP + 0x38:
            return self.config
        if OP + 0x400 <= off < OP + 0x400 + 16 * len(self.ports):
            n = (off - OP - 0x400) // 16
            return self._portsc(n) if (off - OP - 0x400) % 16 == 0 else 0
        if off == RTSOFF + 0x20:
            return self.iman
        if off == XECP:
            return 1 | (4 << 8) | self.legsup        # legacy, next 4 dwords on
        if off == XECP + 4:
            return self.legctl
        if off == XECP + 16:
            return 2 | (5 << 8) | (2 << 24)          # USB 2 protocol
        if off == XECP + 16 + 4:
            return 0x20425355                        # "USB "
        if off == XECP + 16 + 8:
            return 1 | (self.usb2_ports << 8)
        if off == XECP + 36:
            return 2 | (0 << 8) | (3 << 24)          # USB 3, last
        if off == XECP + 36 + 4:
            return 0x20425355
        if off == XECP + 36 + 8:
            return (self.usb2_ports + 1) | (self.usb3_ports << 8)
        return self.regs.get(off, 0)

    def write(self, addr, v):
        off = addr - self.base
        if off == OP:
            self._usbcmd(v)
        elif off == OP + 4:
            self.usbsts &= ~(v & ((1 << 2) | (1 << 3) | (1 << 4) | (1 << 10)))
        elif off == OP + 0x18:
            self.crcr_lo = v
        elif off == OP + 0x1C:
            self.crcr_hi = v
            self.cmd_deq = ((self.crcr_hi << 32) | self.crcr_lo) & ~0x3F
            self.cmd_ccs = self.crcr_lo & 1
        elif off == OP + 0x38:
            self.config = v & 0xFF
        elif OP + 0x400 <= off < OP + 0x400 + 16 * len(self.ports):
            if (off - OP - 0x400) % 16 == 0:
                self._portsc_write((off - OP - 0x400) // 16, v)
        elif off == RTSOFF + 0x20:
            self.iman = (self.iman & ~2 | v & 2) & ~(v & 1)
        elif off == RTSOFF + 0x20 + 0x14:            # ERSTBA high: the ring starts
            self.regs[off] = v
            base = (v << 32) | self.regs.get(RTSOFF + 0x30, 0)
            seg = u64(base) & ~0x3F
            size = u32(base + 8) & 0xFFFF
            self.erst = (seg, size)
            self.evt_enq, self.evt_pcs = 0, 1
            self.log.append(("erst", seg, size, self.regs.get(RTSOFF + 0x28, 0)))
        elif off == XECP:
            self.log.append(("legsup", v))
            if v & (1 << 24):
                self.legsup |= 1 << 24
                if not self.stubborn:
                    self.legsup &= ~(1 << 16)
            if not (v & (1 << 16)):
                self.legsup &= ~(1 << 16)
        elif off == XECP + 4:
            self.legctl = (self.legctl & ~0xE0000000 & ~0xFFFF) | (v & 0xFFFF)
            self.legctl &= ~(v & 0xE0000000)
            self.log.append(("legctl", v))
        elif DBOFF <= off < DBOFF + 4 * 256:
            self._doorbell((off - DBOFF) // 4, v)
        else:
            self.regs[off] = v

    def reg64(self, off):
        return self.regs.get(off, 0) | (self.regs.get(off + 4, 0) << 32)

    # ---- USBCMD ----------------------------------------------------------------
    def _usbcmd(self, v):
        if v & 2:                                    # HCRST
            self.log.append(("hcrst",))
            keep = self.log
            self._power_on()
            self.log = keep
            self.usbcmd = 2
            self.hcrst_left = 2
            self.cnr_left = self.cnr_reads_after_reset
            return
        self.usbcmd = v
        if v & 1:
            self.usbsts &= ~1
        else:
            self.usbsts |= 1

    # ---- ports -----------------------------------------------------------------
    def _portsc(self, n):
        p = self.ports[n]
        return p.ccs | (p.ped << 1) | PORT_PP | (p.speed << 10) | p.changes | ((0 if p.ped else 5) << 5)

    def _portsc_write(self, n, v):
        p = self.ports[n]
        self.log.append(("portsc", n + 1, v))
        p.changes &= ~(v & CHANGES)
        if v & PORT_PED:
            p.ped = 0
        if (v & PORT_PR) and p.ccs:
            p.resets += 1
            if p.major == 2 or p.dev.speed < 4:
                p.ped, p.speed = 1, p.dev.speed
            else:
                p.ped, p.speed = 1, p.dev.speed
            p.changes |= PORT_PRC
            self._port_event(n + 1)
        if (v & PORT_WPR) and p.ccs and p.major == 3:
            p.warm_resets += 1
            p.ped, p.speed = 1, p.dev.speed
            p.changes |= PORT_PRC | PORT_WRC
            self._port_event(n + 1)

    def _port_event(self, port_no):
        if self._running() and self.erst:
            self.post(port_no << 24, CC_SUCCESS << 24, 34 << 10)

    # ---- events ----------------------------------------------------------------
    def post(self, param, status, control):
        seg, size = self.erst
        deq = self.reg64(RTSOFF + 0x38) & ~0xF
        nxt = (self.evt_enq + 1) % size
        if seg + nxt * 16 == deq:
            self.ring_full += 1                       # would overrun the consumer
        wr(seg + self.evt_enq * 16, struct.pack("<QII", param, status, control | self.evt_pcs))
        self.evt_enq += 1
        if self.evt_enq == size:
            self.evt_enq = 0
            self.evt_pcs ^= 1
        self.events_posted += 1
        self.iman |= 1
        self.usbsts |= 1 << 3

    def _complete(self, trb, cc, slot=0):
        self.post(trb, cc << 24, (33 << 10) | (slot << 24))

    # ---- rings -----------------------------------------------------------------
    def _next(self, deq, ccs):
        """The TRB at DEQ if the controller owns it, following links:
        (address, param, status, control, deq, ccs) or None."""
        for _ in range(4):
            param, status, control = struct.unpack("<QII", rd(deq, 16))
            if (control & 1) != ccs:
                return None
            if (control >> 10) & 63 == 6:            # link
                if control & 2:
                    ccs ^= 1
                deq = param & ~0xF
                continue
            return deq, param, status, control, deq + 16, ccs
        return None

    def _doorbell(self, target, v):
        if target == 0:
            self._commands()
        elif not self.deaf:
            self._transfer(target, v & 0xFF)

    def _commands(self):
        while True:
            t = self._next(self.cmd_deq, self.cmd_ccs)
            if t is None:
                return
            addr, param, status, control, self.cmd_deq, self.cmd_ccs = t
            kind = (control >> 10) & 63
            sid = control >> 24
            self.log.append(("cmd", kind, sid))
            cc, out_slot = self._command(kind, param, control, sid)
            self._complete(addr, cc, out_slot)

    def _walk(self, dev, route):
        """From a root port's device down the route string's tiers: the
        device there, or None when a hub on the way has that port off."""
        while route:
            n = route & 15
            route >>= 4
            ports = getattr(dev, "hub_ports", None)
            if not ports or not (1 <= n <= len(ports)):
                return None
            hp = ports[n - 1]
            if not (hp.enabled and hp.dev):
                return None
            dev = hp.dev
        return dev

    def _reachable(self, slot):
        port = self.ports[slot.port - 1]
        if port.dev is None or not port.ped:
            return False
        return self._walk(port.dev, slot.route) is slot.dev

    def _ctx(self, base, i):
        return base + i * self.ctx

    def _command(self, kind, param, control, sid):
        if kind == 23:                               # no-op
            return CC_SUCCESS, 0
        if kind == 9:                                # enable slot
            for s in range(1, self.config + 1):
                if s not in self.slots:
                    self.slots[s] = Slot(s)
                    return CC_SUCCESS, s
            return CC_NO_SLOTS, 0
        slot = self.slots.get(sid)
        if slot is None:
            return CC_TRB, sid
        if kind == 10:                               # disable slot
            del self.slots[sid]
            return CC_SUCCESS, sid
        inp = param & ~0xF
        if kind == 11:                               # address device
            add = u32(inp + 4)
            if add & 3 != 3:
                return CC_TRB, sid
            sc = self._ctx(inp, 1)
            port_no = (u32(sc + 4) >> 16) & 0xFF
            if not (1 <= port_no <= len(self.ports)):
                return CC_TRB, sid
            p = self.ports[port_no - 1]
            if not (p.ccs and p.ped):
                return CC_TRANSACTION, sid
            route = u32(sc) & 0xFFFFF
            dev = self._walk(p.dev, route)
            if dev is None:
                return CC_TRANSACTION, sid
            ep0 = self._ctx(inp, 2)
            d1 = u32(ep0 + 4)
            tr = u64(ep0 + 8)
            slot.port = port_no
            slot.dev = dev                           # what answers at its address
            slot.address = sid
            slot.route = route
            slot.tt = u32(sc + 8) & 0xFFFF
            slot.mtt = (u32(sc) >> 25) & 1
            slot.speed = (u32(sc) >> 20) & 15
            slot.eps = {1: Endpoint(tr & ~0xF, tr & 1, d1 >> 16, (d1 >> 3) & 7)}
            out = u64(self.dcbaa() + sid * 8)
            wr(out, rd(sc, self.ctx))
            wr(out + 12, struct.pack("<I", slot.address | (2 << 27)))
            wr(out + self.ctx, rd(ep0, self.ctx))
            wr(out + self.ctx, struct.pack("<I", EP_RUNNING))
            self.log.append(("address", sid, port_no, slot.speed, d1 >> 16, slot.route))
            self.log.append(("tt", sid, slot.tt, slot.mtt))
            return CC_SUCCESS, sid
        if kind == 13:                               # evaluate context
            add = u32(inp + 4)
            if add & 2:
                mps = u32(self._ctx(inp, 2) + 4) >> 16
                slot.eps[1].mps = mps
                self.log.append(("evaluate", sid, mps))
            return CC_SUCCESS, sid
        if kind == 12:                               # configure endpoint
            add, drop = u32(inp + 4), u32(inp)
            for dci in range(2, 32):
                if drop & (1 << dci):
                    slot.eps.pop(dci, None)
                if add & (1 << dci):
                    ec = self._ctx(inp, dci + 1)
                    d1 = u32(ec + 4)
                    tr = u64(ec + 8)
                    slot.eps[dci] = Endpoint(tr & ~0xF, tr & 1, d1 >> 16, (d1 >> 3) & 7)
                    slot.eps[dci].interval = (u32(ec) >> 16) & 0xFF
                    slot.eps[dci].ctx = (u32(ec), d1, u32(ec + 16))
            sc = self._ctx(inp, 1)
            slot.entries = u32(sc) >> 27
            slot.hub = ((u32(sc) >> 26) & 1, (u32(sc) >> 25) & 1, u32(sc + 4) >> 24, (u32(sc + 8) >> 16) & 3)
            self.log.append(("configure", sid, add, drop))
            return CC_SUCCESS, sid
        dci = (control >> 16) & 31
        ep = slot.eps.get(dci)
        if ep is None:
            return CC_TRB, sid
        if kind == 14:                               # reset endpoint
            if ep.state != EP_HALTED:
                return CC_CTX_STATE, sid
            ep.state = EP_STOPPED
            self.log.append(("reset_ep", sid, dci))
            return CC_SUCCESS, sid
        if kind == 15:                               # stop endpoint
            ep.state = EP_STOPPED
            return CC_SUCCESS, sid
        if kind == 16:                               # set TR dequeue pointer
            if ep.state not in (EP_STOPPED, EP_HALTED):
                return CC_CTX_STATE, sid
            ep.deq, ep.ccs = param & ~0xF, param & 1
            ep.state = EP_STOPPED
            self.log.append(("set_deq", sid, dci))
            return CC_SUCCESS, sid
        return CC_TRB, sid

    def dcbaa(self):
        return self.reg64(OP + 0x30)

    # ---- transfers -----------------------------------------------------------------
    def _xfer_event(self, trb, cc, residual, sid, dci):
        self.post(trb, (cc << 24) | (residual & 0xFFFFFF), (32 << 10) | (sid << 24) | (dci << 16))

    def _transfer(self, sid, dci):
        slot = self.slots.get(sid)
        if slot is None or dci not in slot.eps:
            return
        ep = slot.eps[dci]
        if ep.state == EP_HALTED:
            return
        ep.state = EP_RUNNING
        if dci == 1:
            self._control(slot, ep)
        else:
            self._stream(slot, ep, dci)

    def pump(self):
        """Serve every endpoint waiting with a transfer: queued reports go
        out now (as they would at the next service interval)."""
        for slot in list(self.slots.values()):
            for dci, ep in list(slot.eps.items()):
                if dci != 1 and ep.state == EP_RUNNING:
                    self._stream(slot, ep, dci)

    def _stream(self, slot, ep, dci):
        """Interrupt and bulk: each Normal TRB the device has data for."""
        port = self.ports[slot.port - 1]
        address = (dci // 2) | (0x80 if dci & 1 else 0)
        while True:
            t = self._next(ep.deq, ep.ccs)
            if t is None:
                return
            trb, buf, status, control = t[:4]
            if (control >> 10) & 63 != 1:
                self._xfer_event(trb, CC_TRB, 0, slot.sid, dci)
                ep.state = EP_HALTED
                return
            length = status & 0x1FFFF
            if not self._reachable(slot):
                ep.deq, ep.ccs = t[4], t[5]
                self._xfer_event(trb, CC_TRANSACTION, length, slot.sid, dci)
                ep.state = EP_HALTED
                return
            if address & 0x80:
                data = slot.dev.read(address)
                if data is None:
                    return                           # NAK: the TRB waits
                if data == "stall":
                    ep.deq, ep.ccs = t[4], t[5]
                    self._xfer_event(trb, CC_STALL, length, slot.sid, dci)
                    ep.state = EP_HALTED
                    return
                if len(data) > length:
                    ep.deq, ep.ccs = t[4], t[5]
                    self._xfer_event(trb, 3, 0, slot.sid, dci)   # babble
                    ep.state = EP_HALTED
                    return
                wr(buf, data)
                n = len(data)
            else:
                slot.dev.write(address, rd(buf, length))
                n = length
            ep.deq, ep.ccs = t[4], t[5]
            self.log.append(("stream", slot.sid, dci, n))
            if n < length and control & (1 << 2):
                self._xfer_event(trb, CC_SHORT, length - n, slot.sid, dci)
            elif control & (1 << 5):
                self._xfer_event(trb, CC_SUCCESS, 0, slot.sid, dci)

    def _control(self, slot, ep):
        port = self.ports[slot.port - 1]
        while True:
            t = self._next(ep.deq, ep.ccs)
            if t is None:
                return
            setup_trb, setup, _, control, ep.deq, ep.ccs = t
            if (control >> 10) & 63 != 2:
                self._xfer_event(setup_trb, CC_TRB, 0, slot.sid, 1)
                ep.state = EP_HALTED
                return
            data = None
            t = self._next(ep.deq, ep.ccs)
            if t is None:
                return
            if (t[3] >> 10) & 63 == 3:
                data = t
                ep.deq, ep.ccs = t[4], t[5]
                t = self._next(ep.deq, ep.ccs)
                if t is None:
                    return
            status_trb = t
            ep.deq, ep.ccs = t[4], t[5]
            pkt = struct.pack("<Q", setup)
            out = None
            if data is not None and not (data[3] & (1 << 16)):
                out = rd(data[1], data[2] & 0x1FFFF)
            if not self._reachable(slot):
                self._xfer_event((data or status_trb)[0], CC_TRANSACTION, 0, slot.sid, 1)
                ep.state = EP_HALTED
                return
            self.log.append(("control", slot.sid, pkt.hex()))
            answer = None if self.stall_next_doorbell else slot.dev.control(pkt, out)
            self.stall_next_doorbell = False
            if answer is None:                       # stall
                self._xfer_event((data or status_trb)[0], CC_STALL, 0, slot.sid, 1)
                ep.state = EP_HALTED
                return
            if data is not None and (data[3] & (1 << 16)):
                length = data[2] & 0x1FFFF
                n = min(len(answer), length)
                wr(data[1], answer[:n])
                if n < length and data[3] & (1 << 2):
                    self._xfer_event(data[0], CC_SHORT, length - n, slot.sid, 1)
            if status_trb[3] & (1 << 5):
                self._xfer_event(status_trb[0], CC_SUCCESS, 0, slot.sid, 1)

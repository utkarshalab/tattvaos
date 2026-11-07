"""A simulated I2C-HID device: descriptors at their registers, the
commands the driver sends (power, reset, set report), and a queue of input
reports. xfer(write bytes, read length) answers one transfer.

DWAdapter puts one on a simulated DesignWare bus (sim_dw.py), where a
transfer arrives as start, written bytes, reads, and stop.
"""
import struct

ENXIO = 6
DESC_REG, RDESC_REG, INPUT_REG, CMD_REG, DATA_REG = 0x20, 0x21, 0x22, 0x25, 0x26


class SimI2cHid:
    """An I2C-HID device: descriptors at their registers, commands, a queue
    of input reports."""

    def __init__(self, rdesc, vendor=0x1234, product=0x5678, max_input=64, bcd=0x0100, present=True):
        self.rdesc = rdesc
        self.desc = struct.pack("<HHHHHHHHHHHHHI", 30, bcd, len(rdesc), RDESC_REG, INPUT_REG, max_input,
                                0x23, 0, CMD_REG, DATA_REG, vendor, product, 1, 0)
        self.present = present
        self.power = None
        self.resets = 0
        self.features = {}
        self.queue = []

    def xfer(self, w, rlen):
        if not self.present:
            return -ENXIO, b""
        if len(w) >= 4 and w[0] | w[1] << 8 == CMD_REG:
            b2, op = w[2], w[3]
            if op == 0x08:
                self.power = b2
            elif op == 0x01:
                self.resets += 1
                self.queue.insert(0, b"")            # the reset's empty report
            elif op == 0x03:
                rid, rest = (w[4], w[5:]) if b2 & 0x0F == 0x0F else (b2 & 0x0F, w[4:])
                assert rest[0] | rest[1] << 8 == DATA_REG
                length = rest[2] | rest[3] << 8
                body = rest[4:]
                if rid:
                    assert body[0] == rid
                    body = body[1:]
                assert length == 2 + (1 if rid else 0) + len(body), (length, len(body))
                self.features[rid] = bytes(body)
            return 0, b""
        if len(w) == 2:
            reg = w[0] | w[1] << 8
            data = {DESC_REG: self.desc, RDESC_REG: self.rdesc}.get(reg, b"")
            return 0, data[:rlen].ljust(rlen, b"\x00")
        if len(w) == 0:
            if not self.queue:
                return 0, bytes(rlen)
            r = self.queue.pop(0)
            whole = (struct.pack("<H", len(r) + 2) + r) if r else b"\x00\x00"
            return 0, whole[:rlen].ljust(rlen, b"\x00")
        return 0, b""


class DWAdapter:
    """An I2C-HID device as a sim_dw bus device."""

    def __init__(self, dev):
        self.dev = dev
        self.log = []

    def start(self):
        self.w = []
        self.out = None

    def restart(self):
        pass

    def write(self, b):
        self.w.append(b)
        return True

    def read(self):
        if self.out is None:
            st, data = self.dev.xfer(bytes(self.w), 4096)
            self.out = list(data)
        return self.out.pop(0) if self.out else 0

    def stop(self):
        if self.out is None and self.w:
            self.dev.xfer(bytes(self.w), 0)

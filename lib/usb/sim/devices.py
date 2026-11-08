"""Simulated USB devices for the lib/usb host tests: what they answer on
EP0. control(setup, out_data) returns the bytes of an IN data stage, b""
for success without data, or None to stall."""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests"))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "input", "tests"))
import usb_gen as G  # noqa: E402
import hid_gen as H  # noqa: E402

SPEED_FULL, SPEED_LOW, SPEED_HIGH, SPEED_SUPER = 1, 2, 3, 4


class Device:
    speed = SPEED_FULL
    langs = (0x0409,)

    def __init__(self, device_desc, config_desc, strings=None, speed=None, bos=None):
        self.device_desc = device_desc
        self.config_desc = config_desc
        self.strings = strings or {}
        self.bos = bos
        if speed is not None:
            self.speed = speed
        self.configuration = 0
        self.requests = []
        self.queues = {}            # endpoint address → reports waiting
        self.written = []
        self.protocol = 1           # HID: 1 report, 0 boot
        self.idle = None
        self.leds = []
        self.class_stalls = set()   # HID requests it refuses
        self.report_descs = {}      # interface → HID report descriptor

    def queue(self, address, data):
        self.queues.setdefault(address, []).append(bytes(data) if data != "stall" else data)

    def read(self, address):
        q = self.queues.get(address)
        return q.pop(0) if q else None

    def write(self, address, data):
        self.written.append((address, bytes(data)))

    def descriptor(self, kind, index, lang):
        if kind == 1:
            return self.device_desc
        if kind == 2 and index == 0:
            return self.config_desc
        if kind == 3:
            if index == 0:
                return bytes([2 + 2 * len(self.langs), 3]) + b"".join(struct.pack("<H", x) for x in self.langs)
            if index in self.strings:
                return G.string(self.strings[index])
        if kind == 0x0F and self.bos is not None:
            return self.bos
        return None

    def control(self, setup, out):
        rt, req, value, index, length = struct.unpack("<BBHHH", setup)
        self.requests.append((rt, req, value, index, length))
        if rt == 0x80 and req == 6:
            d = self.descriptor(value >> 8, value & 0xFF, index)
            return None if d is None else d[:length]
        if rt == 0x81 and req == 6 and value >> 8 == 0x22:
            d = self.report_descs.get(index)
            return None if d is None else d[:length]
        if rt == 0x00 and req == 9:
            self.configuration = value
            return b""
        if rt == 0x80 and req == 8:
            return bytes([self.configuration])
        if rt == 0x80 and req == 0:
            return b"\x00\x00"
        if rt == 0x21 and req in self.class_stalls:
            return None
        if rt == 0x21 and req == 0x0B:          # SET_PROTOCOL
            self.protocol = value
            return b""
        if rt == 0x21 and req == 0x0A:          # SET_IDLE
            self.idle = value >> 8
            return b""
        if rt == 0x21 and req == 0x09 and out:  # SET_REPORT
            self.leds.append(out[0])
            return b""
        return None


def keyboard(speed=SPEED_FULL, mps0=8):
    return Device(G.device(vid=0x046D, pid=0xC31C, mps0=mps0, manufacturer=1, product=2, serial=0),
                  G.KEYBOARD_CONFIG, {1: "Logitech", 2: "USB Keyboard"}, speed=speed)


def keyboard_with_media(media=None):
    """A keyboard as most are: the boot keyboard on interface 0, media and
    system keys on interface 1 (report protocol, report IDs 2-4)."""
    media = H.media if media is None else media
    cfg = G.config(G.interface(0, num_ep=1, cls=3, sub=1, proto=1), G.hid(len(H.boot_keyboard)),
                   G.endpoint(0x81, 3, 8, 10),
                   G.interface(1, num_ep=1, cls=3, sub=0, proto=0), G.hid(len(media)),
                   G.endpoint(0x82, 3, 8, 10))
    d = Device(G.device(vid=0x046D, pid=0xC52B, mps0=8, manufacturer=1, product=2, serial=0),
               cfg, {1: "Logitech", 2: "Media Keyboard"})
    d.report_descs = {0: H.boot_keyboard, 1: media}
    return d


def mouse(mps0=64):
    cfg = G.config(G.interface(0, num_ep=1, cls=3, sub=1, proto=2), G.hid(52), G.endpoint(0x81, 3, 4, 10))
    return Device(G.device(vid=0x1BCF, pid=0x0005, mps0=mps0, manufacturer=0, product=1, serial=0),
                  cfg, {1: "Optical Mouse"})


def bluetooth():
    """A high-speed composite device like the laptop's MediaTek radio."""
    cfg = G.config(G.iad(0, 2, 0xE0, 1, 1),
                   G.interface(0, num_ep=3, cls=0xE0, sub=1, proto=1),
                   G.endpoint(0x81, 3, 16, 4), G.endpoint(0x82, 2, 512, 0), G.endpoint(0x02, 2, 512, 0),
                   G.interface(1, num_ep=2, cls=0xE0, sub=1, proto=1),
                   G.endpoint(0x83, 1, 0, 4), G.endpoint(0x03, 1, 0, 4),
                   G.interface(1, alt=1, num_ep=2, cls=0xE0, sub=1, proto=1),
                   G.endpoint(0x83, 1, 9, 4), G.endpoint(0x03, 1, 9, 4))
    return Device(G.device(vid=0x0E8D, pid=0x0608, bcd_usb=0x0210, cls=0xEF, sub=2, proto=1, mps0=64,
                           manufacturer=1, product=2, serial=3),
                  cfg, {1: "MediaTek Inc.", 2: "Wireless_Device", 3: "000000000"}, speed=SPEED_HIGH)


def superspeed_disk():
    cfg = G.config(G.interface(0, num_ep=2, cls=8, sub=6, proto=0x50),
                   G.endpoint(0x81, 2, 1024, 0), G.ss_companion(15),
                   G.endpoint(0x02, 2, 1024, 0), G.ss_companion(15))
    return Device(G.device(vid=0x0781, pid=0x5583, bcd_usb=0x0320, mps0=9, manufacturer=1, product=2, serial=3),
                  cfg, {1: "SanDisk", 2: "Ultra Fit", 3: "4C530001"}, speed=SPEED_SUPER,
                  bos=G.bos(G.cap_usb2(0x06), G.cap_ss()))


class HubPort:
    def __init__(self):
        self.dev = None
        self.powered = self.connected = self.enabled = False
        self.change = 0             # wPortChange bits
        self.resets = 0
        self.warm = 0


class Hub(Device):
    """A USB 2 hub (high speed, one TT or one per port) or a USB 3 hub
    (SuperSpeed). Port status and features as chapter 11 and 10 say; the
    status endpoint reports a bit per port that changed."""

    def __init__(self, ports=4, superspeed=False, multi_tt=False, power_good=50, untrained=()):
        self.ss = superspeed
        speed = SPEED_SUPER if superspeed else SPEED_HIGH
        ep = G.endpoint(0x81, 3, 2, 12 if not superspeed else 8)
        if superspeed:
            ep += G.ss_companion(0, 0, 2)
        cfg = G.config(G.interface(0, num_ep=1, cls=9, proto=1 if multi_tt else 0), ep, attributes=0xE0)
        Device.__init__(self, G.device(vid=0x05E3, pid=0x0626 if superspeed else 0x0610, cls=9,
                                       proto=3 if superspeed else (2 if multi_tt else 1),
                                       bcd_usb=0x0320 if superspeed else 0x0200, mps0=9 if superspeed else 64,
                                       manufacturer=0, product=1, serial=0),
                        cfg, {1: "USB3.0 Hub" if superspeed else "USB2.0 Hub"}, speed=speed)
        self.hub_ports = [HubPort() for _ in range(ports)]
        self.power_good = power_good
        self.depth = None
        self.untrained = set(untrained)
        self.over_current_port = None

    def hub_descriptor(self):
        n = len(self.hub_ports)
        if self.ss:
            return struct.pack("<BBBHBBBHH", 12, 0x2A, n, 0x0000, self.power_good // 2, 0, 0, 0, 0)
        return struct.pack("<BBBHBBBB", 9, 0x29, n, (1 << 5), self.power_good // 2, 100, 0, 0xFF)

    def _changed(self, n):
        bitmap = 1 << n
        self.queue(0x81, bitmap.to_bytes(1 + len(self.hub_ports) // 8, "little"))

    def attach(self, n, dev):
        p = self.hub_ports[n - 1]
        p.dev = dev
        if p.powered:
            p.connected = True
            p.change |= 1
            if self.ss and dev.speed >= SPEED_SUPER and n not in self.untrained:
                p.enabled = True        # the USB 3 link trains by itself
            self._changed(n)

    def detach(self, n):
        p = self.hub_ports[n - 1]
        p.dev, p.connected, p.enabled = None, False, False
        p.change |= 1 | 2
        self._changed(n)

    def over_current(self, n):
        self.hub_ports[n - 1].change |= 8
        self.over_current_port = n
        self._changed(n)

    def port_status(self, n):
        p = self.hub_ports[n - 1]
        s = (1 if p.connected else 0) | (2 if p.enabled else 0)
        if self.over_current_port == n:
            s |= 8
        if self.ss:
            s |= (1 << 9) if p.powered else 0
        else:
            s |= (1 << 8) if p.powered else 0
            if p.enabled and p.dev:
                s |= (1 << 9) if p.dev.speed == SPEED_LOW else 0
                s |= (1 << 10) if p.dev.speed == SPEED_HIGH else 0
        return struct.pack("<HH", s, p.change)

    def control(self, setup, out):
        rt, req, value, index, length = struct.unpack("<BBHHH", setup)
        if rt == 0xA0 and req == 6 and (value >> 8) == (0x2A if self.ss else 0x29):
            self.requests.append((rt, req, value, index, length))
            return self.hub_descriptor()[:length]
        if rt == 0x20 and req == 12:
            self.requests.append((rt, req, value, index, length))
            self.depth = value
            return b""
        if rt in (0xA3, 0x23) and 1 <= index <= len(self.hub_ports):
            self.requests.append((rt, req, value, index, length))
            p = self.hub_ports[index - 1]
            if rt == 0xA3 and req == 0:
                return self.port_status(index)[:length]
            if req == 3 and value == 8:                 # PORT_POWER
                p.powered = True
                if p.dev and not p.connected:
                    self.attach(index, p.dev)
                return b""
            if req == 3 and value in (4, 28):           # PORT_RESET, BH_PORT_RESET
                if p.connected:
                    p.enabled = True
                    if value == 28:
                        p.warm += 1
                        p.change |= 1 << 5
                    else:
                        p.resets += 1
                        p.change |= 1 << 4
                    self._changed(index)
                return b""
            if req == 1:                                # CLEAR_FEATURE
                bit = {16: 0, 17: 1, 18: 2, 19: 3, 20: 4, 29: 5, 25: 6, 26: 7}.get(value)
                if bit is not None:
                    p.change &= ~(1 << bit)
                    if bit == 3:
                        self.over_current_port = None
                    return b""
                if value == 1:
                    p.enabled = False
                    return b""
            return None
        return Device.control(self, setup, out)

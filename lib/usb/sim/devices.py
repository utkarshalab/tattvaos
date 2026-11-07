"""Simulated USB devices for the lib/usb host tests: what they answer on
EP0. control(setup, out_data) returns the bytes of an IN data stage, b""
for success without data, or None to stall."""
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests"))
import usb_gen as G  # noqa: E402

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
        if rt == 0x00 and req == 9:
            self.configuration = value
            return b""
        if rt == 0x80 and req == 8:
            return bytes([self.configuration])
        if rt == 0x80 and req == 0:
            return b"\x00\x00"
        return None


def keyboard(speed=SPEED_FULL, mps0=8):
    return Device(G.device(vid=0x046D, pid=0xC31C, mps0=mps0, manufacturer=1, product=2, serial=0),
                  G.KEYBOARD_CONFIG, {1: "Logitech", 2: "USB Keyboard"}, speed=speed)


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

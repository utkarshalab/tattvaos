"""Descriptor builders for the lib/usb host tests (and, later, the
simulated devices in sim/)."""
import struct


def device(vid=0x1234, pid=0x5678, bcd_usb=0x0200, cls=0, sub=0, proto=0, mps0=64, bcd_dev=0x0100,
           manufacturer=1, product=2, serial=3, configs=1):
    return struct.pack("<BBHBBBBHHHBBBB", 18, 1, bcd_usb, cls, sub, proto, mps0, vid, pid, bcd_dev,
                       manufacturer, product, serial, configs)


def interface(number, alt=0, num_ep=0, cls=0, sub=0, proto=0, string=0):
    return struct.pack("<BBBBBBBBB", 9, 4, number, alt, num_ep, cls, sub, proto, string)


def endpoint(address, attributes, max_packet, interval, extra=b""):
    return struct.pack("<BBBBHB", 7 + len(extra), 5, address, attributes, max_packet, interval) + extra


def ss_companion(burst=0, attributes=0, bytes_per_interval=0):
    return struct.pack("<BBBBH", 6, 0x30, burst, attributes, bytes_per_interval)


def ssp_isoc_companion(bytes_per_interval):
    return struct.pack("<BBHI", 8, 0x31, 0, bytes_per_interval)


def iad(first, count, cls, sub=0, proto=0, string=0):
    return struct.pack("<BBBBBBBB", 8, 0x0B, first, count, cls, sub, proto, string)


def hid(report_len, country=0, extra=()):
    entries = [(0x22, report_len)] + list(extra)
    body = b"".join(struct.pack("<BH", t, n) for t, n in entries)
    return struct.pack("<BBHBB", 6 + len(body), 0x21, 0x0111, country, len(entries)) + body


def cs(kind, body):
    """A class-specific descriptor (0x24 interface, 0x25 endpoint)."""
    return bytes([2 + len(body), kind]) + bytes(body)


def config(*parts, value=1, string=0, attributes=0x80, max_power=50, num_ifaces=None):
    body = b"".join(parts)
    if num_ifaces is None:
        nums = set()
        i = 0
        while i + 1 < len(body):
            if body[i + 1] == 4 and body[i] >= 9:
                nums.add(body[i + 2])
            i += max(body[i], 1)
        num_ifaces = len(nums)
    return struct.pack("<BBHBBBBB", 9, 2, 9 + len(body), num_ifaces, value, string, attributes, max_power) + body


def string(text):
    units = text.encode("utf-16-le")
    return bytes([2 + len(units), 3]) + units


def raw_string(units):
    data = b"".join(struct.pack("<H", u) for u in units)
    return bytes([2 + len(data), 3]) + data


def bos(*caps):
    body = b"".join(caps)
    return struct.pack("<BBHB", 5, 0x0F, 5 + len(body), len(caps)) + body


def cap_usb2(attributes):
    return struct.pack("<BBBI", 7, 0x10, 2, attributes)


def cap_ss(attributes=0, speeds=0x0E, functionality=1, u1=10, u2=2047):
    return struct.pack("<BBBBHBBH", 10, 0x10, 3, attributes, speeds, functionality, u1, u2)


def cap_container(uuid16):
    return struct.pack("<BBBB", 20, 0x10, 4, 0) + bytes(uuid16)


def cap_ssp(sublinks, functionality=0):
    """sublinks: (id, exponent, type, protocol, mantissa)."""
    attrs = b"".join(struct.pack("<I", sid | (lse << 4) | (st << 6) | (lp << 14) | (lsm << 16))
                     for sid, lse, st, lp, lsm in sublinks)
    return struct.pack("<BBBBIHH", 12 + len(attrs), 0x10, 0x0A, 0, len(sublinks) - 1, functionality, 0) + attrs


# a boot keyboard: one interface, one interrupt IN endpoint
KEYBOARD_CONFIG = config(interface(0, num_ep=1, cls=3, sub=1, proto=1),
                         hid(63),
                         endpoint(0x81, 3, 8, 10))

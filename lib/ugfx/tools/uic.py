#!/usr/bin/env python3
"""UIC icon packs (docs/UIC.md): build and dump.

Library:
    Icon(name, viewbox, slots, commands, design_size=0)
    pack(icons) -> bytes        sorted, validated layout, coordinates quantised
    dump(data) -> str           readable listing of a pack

Commands are tuples in viewBox units:
    ('move', x, y) ('line', x, y) ('quad', x1, y1, x, y)
    ('cubic', x1, y1, x2, y2, x, y) ('close',)
    ('fill', slot, rule) ('stroke', slot, join, cap, width) ('opacity', alpha)

Command line:
    uic.py dump <pack.uic>

Development-machine tooling only; not part of any OS image.
"""
import struct
import sys
from dataclasses import dataclass, field

MAGIC = b"UIC\x1a"
OPS = {'end': 0x00, 'move': 0x01, 'line': 0x02, 'quad': 0x03, 'cubic': 0x04, 'close': 0x05,
       'fill': 0x10, 'stroke': 0x11, 'opacity': 0x20}
NAMES = {v: k for k, v in OPS.items()}
COORDS = {'move': 2, 'line': 2, 'quad': 4, 'cubic': 6}


@dataclass
class Icon:
    name: str
    viewbox: tuple
    slots: list
    commands: list
    design_size: int = 0
    frac: int = field(default=None)     # chosen by pack() unless given

    def fraction_bits(self):
        """Largest f <= 14 with every coordinate and width fitting an i16."""
        if self.frac is not None:
            return self.frac
        m = 0.0
        for c in self.commands:
            if c[0] in COORDS:
                m = max([m] + [abs(v) for v in c[1:]])
            elif c[0] == 'stroke':
                m = max(m, abs(c[4]))
        f = 14
        while f > 0 and round(m * (1 << f)) > 32767:
            f -= 1
        return f


def quantise(v, f):
    q = round(v * (1 << f))
    if not -32768 <= q <= 32767:
        raise ValueError(f"coordinate {v} does not fit at {f} fraction bits")
    return q


def body(icon):
    f = icon.fraction_bits()
    out = struct.pack("<4fBBH", *icon.viewbox, f, len(icon.slots), 0)
    out += b"".join(struct.pack("<I", c) for c in icon.slots)
    for c in icon.commands:
        op = c[0]
        out += bytes([OPS[op]])
        if op in COORDS:
            out += struct.pack(f"<{COORDS[op]}h", *(quantise(v, f) for v in c[1:]))
        elif op == 'fill':
            out += bytes([c[1], c[2]])
        elif op == 'stroke':
            _, slot, join, cap, width = c
            out += bytes([slot, join | cap << 4]) + struct.pack("<h", quantise(width, f))
        elif op == 'opacity':
            out += bytes([c[1]])
    return out + bytes([OPS['end']])


def pack(icons, raw_bodies=None):
    """A UIC pack. raw_bodies (name, size) -> bytes replaces bodies (tests)."""
    entries = sorted(icons, key=lambda i: (i.name.encode(), i.design_size))
    strings, data, index = b"", b"", []
    for icon in entries:
        name = icon.name.encode()
        b = (raw_bodies or {}).get((icon.name, icon.design_size)) or body(icon)
        index.append((len(strings), len(data), len(b), len(name), icon.design_size))
        strings += name
        data += b + b"\0" * (-len(b) % 4)
    index_off = 32
    strings_off = index_off + 16 * len(index)
    data_off = strings_off + len(strings) + (-(strings_off + len(strings)) % 4)
    out = MAGIC + struct.pack("<HHIIIIII", 1, 0, len(index), index_off, strings_off, len(strings),
                              data_off, len(data))
    out += b"".join(struct.pack("<IIIHH", *e) for e in index)
    out += strings + b"\0" * (data_off - strings_off - len(strings)) + data
    return out


def dump(data):
    lines = []
    magic, ver, flags, n, io, so, ss, do, ds = struct.unpack_from("<4sHHIIIIII", data)
    lines.append(f"UIC version {ver}, flags {flags}, {n} icons")
    for i in range(n):
        no, bo, bs, nl, size = struct.unpack_from("<IIIHH", data, io + 16 * i)
        name = data[so + no:so + no + nl].decode(errors="replace")
        b = data[do + bo:do + bo + bs]
        x, y, w, h, f, s, _ = struct.unpack_from("<4fBBH", b)
        slots = struct.unpack_from(f"<{s}I", b, 20)
        lines.append(f"icon {name!r} design size {size or 'scalable'}: viewBox {x:g} {y:g} {w:g} {h:g}, "
                     f"{f} fraction bits, slots " + " ".join(f"{c:08X}" for c in slots))
        p, scale = 20 + 4 * s, 1 / (1 << f)
        while p < len(b):
            op = NAMES.get(b[p], f"?{b[p]:02X}")
            p += 1
            if op in COORDS:
                vals = struct.unpack_from(f"<{COORDS[op]}h", b, p)
                p += 2 * len(vals)
                lines.append(f"  {op} " + " ".join(f"{v * scale:g}" for v in vals))
            elif op == 'fill':
                lines.append(f"  fill slot {b[p]} {'even-odd' if b[p + 1] else 'nonzero'}")
                p += 2
            elif op == 'stroke':
                (w,) = struct.unpack_from("<h", b, p + 2)
                lines.append(f"  stroke slot {b[p]} join {b[p + 1] & 15} cap {b[p + 1] >> 4} width {w * scale:g}")
                p += 4
            elif op == 'opacity':
                lines.append(f"  opacity {b[p]}")
                p += 1
            else:
                lines.append(f"  {op}")
                if op == 'end':
                    break
    return "\n".join(lines)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "dump":
        print(dump(open(sys.argv[2], "rb").read()))
    else:
        sys.exit(__doc__)

"""HID report descriptors built item by item, for tests.

Also the descriptors the suites share: a boot keyboard, a mouse, and a
five-finger touchpad laid out like a precision touchpad.
"""

CONST, VAR, REL = 1, 2, 4      # main item data bits


def item(typ, tag, value=None, size=None):
    if value is None:
        return bytes([(tag << 4) | (typ << 2)])
    if size is None:
        size = 1 if -128 <= value <= 255 else 2 if -32768 <= value <= 65535 else 4
    code = {1: 1, 2: 2, 4: 3}[size]
    return bytes([(tag << 4) | (typ << 2) | code]) + (value & ((1 << (8 * size)) - 1)).to_bytes(size, "little")


def G(tag):
    return lambda v, size=None: item(1, tag, v, size)


def L(tag):
    return lambda v, size=None: item(2, tag, v, size)


UsagePage, LogMin, LogMax, PhysMin, PhysMax, UnitExp, Unit, Size, ReportID, Count, Push, Pop = \
    [G(t) for t in range(12)]
Usage, UsageMin, UsageMax = L(0), L(1), L(2)


def Input(flags):
    return item(0, 8, flags)


def Output(flags):
    return item(0, 9, flags)


def Feature(flags):
    return item(0, 11, flags)


def Collection_(t):
    return item(0, 10, t)


End = item(0, 12)
APPLICATION, PHYSICAL, LOGICAL = 1, 0, 2

boot_keyboard = b"".join([
    UsagePage(1), Usage(6), Collection_(APPLICATION),
    UsagePage(7), UsageMin(0xE0), UsageMax(0xE7), LogMin(0), LogMax(1), Size(1), Count(8), Input(VAR),
    Count(1), Size(8), Input(CONST),
    Count(5), Size(1), UsagePage(8), UsageMin(1), UsageMax(5), Output(VAR),
    Count(1), Size(3), Output(CONST),
    Count(6), Size(8), LogMin(0), LogMax(101), UsagePage(7), UsageMin(0), UsageMax(101), Input(0),
    End])

mouse = b"".join([
    UsagePage(1), Usage(2), Collection_(APPLICATION), Usage(1), Collection_(PHYSICAL),
    UsagePage(9), UsageMin(1), UsageMax(3), LogMin(0), LogMax(1), Count(3), Size(1), Input(VAR),
    Count(1), Size(5), Input(CONST),
    UsagePage(1), Usage(0x30), Usage(0x31), Usage(0x38), LogMin(-127), LogMax(127), Size(8), Count(3),
    Input(VAR | REL),
    End, End])


def finger():
    return b"".join([
        UsagePage(0x0D), Usage(0x22), Collection_(LOGICAL),
        LogMin(0), LogMax(1), Size(1), Count(1), Usage(0x47), Input(VAR),      # confidence
        Usage(0x42), Input(VAR),                                                # tip switch
        Count(6), Input(CONST),
        Size(8), Count(1), LogMax(127), Usage(0x51), Input(VAR),                # contact ID
        UsagePage(1), Push(0), Size(16), UnitExp(0x0E), Unit(0x11), LogMax(4095, 2), PhysMax(1220, 2),
        Usage(0x30), Input(VAR), PhysMax(780, 2), LogMax(2470, 2), Usage(0x31), Input(VAR), Pop(0),
        End])


touchpad = b"".join([
    UsagePage(0x0D), Usage(0x05), Collection_(APPLICATION), ReportID(1),
    finger(), finger(), finger(), finger(), finger(),
    UsagePage(0x0D), Size(16), Count(1), LogMax(0xFFFF, 4), Usage(0x56), Input(VAR),  # scan time
    Usage(0x54), Size(8), LogMax(127), Input(VAR),                                     # contact count
    UsagePage(9), Usage(1), LogMax(1), Size(1), Count(1), Input(VAR), Count(7), Input(CONST),
    UsagePage(0x0D), ReportID(2), Usage(0x55), Count(1), Size(4), LogMax(5), Feature(VAR),  # max contacts
    Usage(0x59), Feature(VAR),
    End,
    UsagePage(0x0D), Usage(0x0E), Collection_(APPLICATION), ReportID(3),
    Usage(0x22), Collection_(LOGICAL), Usage(0x52), LogMax(10), Size(8), Count(1), Feature(VAR), End,
    End])

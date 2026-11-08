"""lib/usb/kernel.asm: finding xHCI controllers on PCI, sizing and mapping
their registers, starting them, devices at boot and plugged in later.

usage: python3 test_kernel.py path/to/ukstub.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
import devices as D  # noqa: E402
import xhci_sim as X  # noqa: E402

lib = C.CDLL(sys.argv[1])
KEY, BUTTON = 1, 4
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731


def fn(n, res, *args):
    f = getattr(lib, n)
    f.restype = res
    f.argtypes = list(args)
    return f


init = fn("usb_kernel_init", None)
poll = fn("usb_kernel_poll", None)
input_init = fn("input_init", None)
register = fn("ut_input_register_callback", C.c_int64, C.c_void_p, C.c_void_p)
pump = fn("input_pump", C.c_int32)
dev_info = fn("ut_input_device_info", C.c_int64, C.c_uint32)


# ---- PCI configuration space ----------------------------------------------------
class Function:
    def __init__(self, vid, did, cls, multi=False, bar0=0, bar1=0, size=0, bar64=True):
        self.cfg = bytearray(256)
        struct.pack_into("<HH", self.cfg, 0, vid, did)
        struct.pack_into("<I", self.cfg, 8, (cls << 8) | 0x01)
        self.cfg[0x0E] = 0x80 if multi else 0
        struct.pack_into("<H", self.cfg, 4, 0x0006)        # firmware left it on
        struct.pack_into("<II", self.cfg, 0x10, bar0, bar1)
        self.size, self.bar64 = size, bar64
        self.sizing = set()

    def read(self, off):
        if off in self.sizing:
            if off == 0x10:
                return (~(self.size - 1) & 0xFFFFFFF0) | (self.cfg[0x10] & 0xF)
            return 0xFFFFFFFF if self.bar64 else 0
        return struct.unpack_from("<I", self.cfg, off)[0]

    def write(self, off, v):
        if off in (0x10, 0x14) and v == 0xFFFFFFFF:
            self.sizing.add(off)
            return
        self.sizing.discard(off)
        struct.pack_into("<I", self.cfg, off, v)


pci = {}
cfg_writes = []


def bdf(b, d, f):
    return (b << 8) | (d << 3) | f


def cfg_read(b, off):
    f = pci.get(b)
    return f.read(off) if f else 0xFFFFFFFF


def cfg_write(b, off, v):
    cfg_writes.append((b, off, v))
    if b in pci:
        pci[b].write(off, v)


sims = []
ranges = []
maps = []


def which(addr):
    for s in sims:
        if s.base <= addr < s.base + 0x10000:
            return s
    raise AssertionError(hex(addr))


def take_range(size):
    s = sims[len(ranges)]
    ranges.append(size)
    return s.base


ARENA = C.create_string_buffer((USB_POOL := 512 * 4096) + 4096)
hooks = [C.CFUNCTYPE(C.c_uint32, C.c_uint32, C.c_uint32)(cfg_read),
         C.CFUNCTYPE(None, C.c_uint32, C.c_uint32, C.c_uint32)(cfg_write),
         C.CFUNCTYPE(C.c_uint64, C.c_uint64)(take_range),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint64, C.c_uint64)(lambda v, p, f: maps.append((v, p, f))),
         C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: which(a).read(a) & 0xFFFFFFFF),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: which(a).write(a, v)),
         C.CFUNCTYPE(C.c_uint64)(lambda: 0), C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)]
for name, cb in zip(("ukstub_cfg_read_fn", "ukstub_cfg_write_fn", "ukstub_range_fn", "ukstub_map_fn",
                     "usb_rd32_fn", "usb_wr32_fn", "input_irq_off_fn", "input_irq_restore_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


class Event(C.Structure):
    _fields_ = [("type", C.c_uint32), ("code", C.c_int32), ("value", C.c_int32),
                ("device", C.c_uint32), ("time", C.c_uint64)]


events = []
on_event = C.CFUNCTYPE(None, C.c_void_p, C.c_void_p)(
    lambda e, c: events.append((Event.from_address(e).type, Event.from_address(e).code,
                                Event.from_address(e).value, Event.from_address(e).device)))


def console():
    n = u32("kstub_out_len").value
    return C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n).decode(errors="replace")


def boot(pages=True):
    for n in ("xhci_hc_count", "usb_device_total", "usb_hid_count", "kstub_out_len", "ukstub_vmas"):
        u32(n).value = 0
    C.memset(C.addressof(C.c_uint8.in_dll(lib, "usb_k_ports")), 0, 4 * 32)
    C.c_uint64.in_dll(lib, "kstub_pages").value = ((C.addressof(ARENA) + 4095) & ~4095) if pages else 0
    ranges.clear()
    maps.clear()
    cfg_writes.clear()
    input_init()
    register(C.cast(on_event, C.c_void_p), 0)
    events.clear()
    init()


def take():
    for s in sims:
        s.pump()
    poll()
    pump()
    out = [e for e in events if e[0] != 10]
    events.clear()
    return out


def code_shown():
    text = console()
    mark = "type this code on it, then Enter: "
    return text[text.rindex(mark) + len(mark):].split()[0]


DIGIT = {str(n): 0x1D + n for n in range(1, 10)} | {"0": 0x27}


def type_code(dev, code):
    for ch in code:
        dev.queue(0x81, kreport(0, DIGIT[ch]))
        dev.queue(0x81, kreport(0))
    dev.queue(0x81, kreport(0, 0x28))
    dev.queue(0x81, kreport(0))
    take()


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def kreport(mods=0, *keys):
    return bytes([mods, 0] + list(keys) + [0] * (6 - len(keys)))


# ---- this laptop, roughly: two AMD xHCI functions of one device -------------------
A, B = bdf(3, 0, 3), bdf(3, 0, 4)
pci.clear()
pci[bdf(0, 0, 0)] = Function(0x1022, 0x1630, 0x060000)
pci[bdf(3, 0, 0)] = Function(0x1002, 0x164C, 0x030000, multi=True)
pci[A] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xFD300004, bar1=0, size=1 << 20)
pci[B] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xFD200004, bar1=0, size=1 << 20)
pci[bdf(3, 0, 5)] = Function(0x1022, 0x15E3, 0x040300)
pci[bdf(4, 0, 0)] = Function(0x1022, 0x7808, 0x0C0320)              # EHCI: not this driver's
pci[bdf(4, 0, 1)] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xFE000004, size=1 << 20)
# 04:00.0 says it has one function, so 04:00.1 must not be looked at
sims[:] = [X.XhciSim(usb2_ports=2, usb3_ports=2), X.XhciSim(usb2_ports=2, usb3_ports=2)]
kbd, ms = D.keyboard(), D.mouse()
sims[0].attach(1, kbd)
sims[1].attach(2, ms)
boot()
check("two controllers started, not the one on a single-function device's function 1",
      (u32("xhci_hc_count").value, list((C.c_uint32 * 2).in_dll(lib, "usb_k_bdf"))), (2, [A, B]))
check("BARs sized and put back", [struct.unpack_from("<II", pci[x].cfg, 0x10) for x in (A, B)],
      [(0xFD300004, 0), (0xFD200004, 0)])
check("decoding off while sizing, then memory, bus master, no INTx",
      [[v for b, o, v in cfg_writes if b == x and o == 4] for x in (A, B)], [[0, 0x406], [0, 0x406]])
check("1 MB each, mapped page by page, uncached, no execute",
      (ranges, len(maps), {f for v, p, f in maps}, u32("ukstub_vmas").value),
      ([1 << 20, 1 << 20], 512, {(1 << 1) | (1 << 3) | (1 << 4) | (1 << 63)}, 2))
check("the right physical pages", (maps[0][1], maps[255][1], maps[256][1], maps[256][0] - sims[1].base),
      (0xFD300000, 0xFD3FF000, 0xFD200000, 0))
out = console()
check("console: controllers", ["USB: xHCI 03:00.3 1022:1639 registers at 00000000fd300000, ports 4, running" in out,
                               "USB: xHCI 03:00.4 1022:1639 registers at 00000000fd200000, ports 4, running" in out],
      [True, True])
check("console: devices", ["USB:   port 1: 046d:c31c full, USB Keyboard (input)" in out,
                           "USB:   port 2: 1bcf:0005 full, Optical Mouse (input)" in out], [True, True])
check("input devices", [C.c_char_p.from_address(dev_info(i) + 8).value for i in (1, 2)],
      [b"USB keyboard", b"USB mouse"])
kbd.queue(0x81, kreport(0, 0x17))
ms.queue(0x81, bytes([1, 0, 0, 0]))
check("typing and clicking through the fiber's poll", take(), [(KEY, 20, 1, 1), (BUTTON, 0, 1, 2)])

# plugged in later
k2 = D.keyboard()
sims[0].attach(3, D.superspeed_disk())
sims[1].attach(1, k2)
take()
out = console()
check("new devices found by the poll", ("port 3: 0781:5583 5G, Ultra Fit" in out,
                                        "port 1: 046d:c31c full, USB Keyboard (input)" in out,
                                        u32("usb_device_total").value), (True, True, 4))
check("a keyboard after start-up: its code on the console", len(code_shown()), 6)
k2.queue(0x81, kreport(0, 0x04))
check("not a key from it before the code", take(), [])
type_code(k2, code_shown())
check("accepted", "USB: keyboard accepted" in console(), True)
k2.queue(0x81, kreport(0, 0x04))
check("the new keyboard types", take(), [(KEY, 30, 1, 3)])
check("a quiet poll changes nothing", (take(), u32("usb_device_total").value), ([], 4))
sims[1].detach(1)
take()
check("unplugged: its port free, said on the console",
      (C.c_uint8.from_address(C.addressof(C.c_uint8.in_dll(lib, "usb_k_ports")) + 32).value & 2,
       "USB:   gone from port 1" in console(), u32("usb_device_total").value), (0, True, 3))
k3 = D.keyboard()
sims[1].attach(1, k3)
take()
type_code(k3, code_shown())
k3.queue(0x81, kreport(0, 0x05))
check("plugged back in: enumerated again, a new code, typing",
      (u32("usb_device_total").value, take()), (4, [(KEY, 48, 1, 3)]))

# a hub at boot: what is on it counts as there at start-up
# (function 0 of the device first, or nothing behind it is looked at)
pci.clear()
pci[bdf(3, 0, 0)] = Function(0x1002, 0x164C, 0x030000, multi=True)
pci[A] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xFD300004, bar1=0, size=1 << 20)
sims[:] = [X.XhciSim(usb2_ports=2, usb3_ports=2)]
hub = D.Hub(ports=4)
hk = D.keyboard()
hub.attach(2, hk)
sims[0].attach(1, hub)
boot()
out = console()
check("a hub at boot and the keyboard on it, each on its own line",
      ("USB:   port 1: 05e3:0610 high, USB2.0 Hub (hub)" in out, "USB:   port 1.2: 046d:c31c full, USB Keyboard (input)" in out,
       "code" in out), (True, True, False))
hk.queue(0x81, kreport(0, 0x04))
check("it types without a code", take(), [(KEY, 30, 1, 1)])
pool = lambda: C.c_uint64.in_dll(lib, "usb_pool_next").value  # noqa: E731
marks = []
for _ in range(10):
    hub.attach(3, D.mouse())
    take()
    hub.detach(3)
    take()
    marks.append(pool())
check("ten mice in and out: the pool's freed blocks used again", (len(set(marks[1:])), marks[0] == marks[-1]),
      (1, True))
sims[0].detach(1)
take()
check("the hub pulled out: both gone", (u32("usb_device_total").value, u32("usb_hub_count").value), (0, 0))

# ---- what can go wrong ------------------------------------------------------------
pci.clear()
pci[bdf(0, 0, 0)] = Function(0x1022, 0x1630, 0x060000)
sims[:] = []
boot()
check("no controller", "USB: no xHCI controller" in console(), True)
pci[bdf(2, 0, 0)] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xE001, size=32)
boot()
check("an I/O BAR", ("03:00" not in console(), ": unusable registers" in console(), u32("usb_k_failed").value),
      (True, True, 1))
pci.clear()
pci[bdf(2, 0, 0)] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xFD300004, size=1 << 20)
C.c_uint32.in_dll(lib, "ukstub_ram").value = 1
sims[:] = [X.XhciSim()]
boot()
check("registers in RAM: refused, command put back",
      (": unusable registers" in console(), struct.unpack_from("<H", pci[bdf(2, 0, 0)].cfg, 4)[0], len(maps)),
      (True, 6, 0))
C.c_uint32.in_dll(lib, "ukstub_ram").value = 0
sims[:] = [X.XhciSim(reset_sticks=True)]
boot()
check("a controller that does not start", (": did not start, step 3" in console(), u32("xhci_hc_count").value),
      (True, 0))
pci[bdf(2, 0, 0)] = Function(0x1022, 0x1639, 0x0C0330, bar0=0x12345000, bar64=False, size=1 << 16)
sims[:] = [X.XhciSim()]
boot()
check("a 32-bit BAR of 64 KB", (u32("xhci_hc_count").value, ranges, maps[0][1]), (1, [1 << 16], 0x12345000))
boot(pages=False)
check("no memory for the stack", ("USB: no memory for the stack" in console(), u32("xhci_hc_count").value), (True, 0))

# ---- the USB policy from the boot files -------------------------------------------
pci.clear()
pci[bdf(3, 0, 0)] = Function(0x1002, 0x164C, 0x030000, multi=True)
pci[A] = Function(0x1022, 0x1639, 0x0C0330, bar0=0xFD300004, bar1=0, size=1 << 20)
sims[:] = [X.XhciSim(usb2_ports=2, usb3_ports=2)]
conf = C.create_string_buffer(b"# test\nnew_keyboard_check = off\nbogus line\n")
C.c_uint64.in_dll(lib, "ukstub_boot_ptr").value = C.addressof(conf)
C.c_uint64.in_dll(lib, "ukstub_boot_len").value = len(conf.value)
u32("usb_new_keyboard_check").value = 1
boot()
check("conf/usb/usb.conf read at start-up, what it set and refused said",
      ("USB: conf/usb/usb.conf: 1 settings, lines refused: 1; new-keyboard check off" in console(),
       u32("usb_new_keyboard_check").value), (True, 0))
k4 = D.keyboard()
sims[0].attach(2, k4)
take()
k4.queue(0x81, kreport(0, 0x04))
check("so a keyboard after start-up types at once", (take(), "type this code" in console()),
      ([(KEY, 30, 1, 1)], False))
C.c_uint64.in_dll(lib, "ukstub_boot_ptr").value = 0
C.c_uint64.in_dll(lib, "ukstub_boot_len").value = 0
u32("usb_new_keyboard_check").value = 1
sims[:] = [X.XhciSim(usb2_ports=2, usb3_ports=2)]
boot()
check("no boot files: no line, the default kept", ("conf/usb" in console(), u32("usb_new_keyboard_check").value),
      (False, 1))

print(f"test_kernel: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

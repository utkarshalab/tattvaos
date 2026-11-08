"""lib/ubt/kernel.asm: Bluetooth radios found by the USB kernel glue, said
on the console after their device's line, polled from the USB poll.

usage: python3 test_bt_kernel.py path/to/bkstub.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sim"))
sys.path.insert(0, os.path.join(HERE, "..", "..", "usb", "sim"))
import hci_usb as B  # noqa: E402
import xhci_sim as X  # noqa: E402

lib = C.CDLL(sys.argv[1])
u32 = lambda n: C.c_uint32.in_dll(lib, n)  # noqa: E731
bt_init = getattr(lib, "ubt_kernel_init")
usb_init = getattr(lib, "usb_kernel_init")
usb_poll = getattr(lib, "usb_kernel_poll")

XHCI = (3 << 8) | (0 << 3) | 3
cfg = {}


def function(vid, did, cls, multi=False, bar0=0, size=0):
    c = bytearray(256)
    struct.pack_into("<HH", c, 0, vid, did)
    struct.pack_into("<I", c, 8, (cls << 8) | 1)
    c[0x0E] = 0x80 if multi else 0
    struct.pack_into("<H", c, 4, 6)
    struct.pack_into("<I", c, 0x10, bar0)
    return {"cfg": c, "size": size, "sizing": False}


def cfg_read(bdf, off):
    f = cfg.get(bdf)
    if not f:
        return 0xFFFFFFFF
    if off == 0x10 and f["sizing"]:
        return (~(f["size"] - 1) & 0xFFFFFFF0) | (f["cfg"][0x10] & 0xF)
    if off == 0x14 and f["sizing"]:
        return 0xFFFFFFFF
    return struct.unpack_from("<I", f["cfg"], off)[0]


def cfg_write(bdf, off, v):
    f = cfg.get(bdf)
    if not f:
        return
    if off in (0x10, 0x14) and v == 0xFFFFFFFF:
        f["sizing"] = True
        return
    if off == 0x10:
        f["sizing"] = False
    struct.pack_into("<I", f["cfg"], off, v)


sim = None
ARENA = C.create_string_buffer(512 * 4096 + 4096)




hooks = [C.CFUNCTYPE(C.c_uint32, C.c_uint32, C.c_uint32)(cfg_read),
         C.CFUNCTYPE(None, C.c_uint32, C.c_uint32, C.c_uint32)(cfg_write),
         C.CFUNCTYPE(C.c_uint64, C.c_uint64)(lambda size: sim.base),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint64, C.c_uint64)(lambda v, p, f: None),
         C.CFUNCTYPE(C.c_uint32, C.c_uint64)(lambda a: sim.read(a) & 0xFFFFFFFF),
         C.CFUNCTYPE(None, C.c_uint64, C.c_uint32)(lambda a, v: sim.write(a, v)),
         C.CFUNCTYPE(C.c_uint64)(lambda: 0), C.CFUNCTYPE(None, C.c_uint64)(lambda f: None)]
for name, cb in zip(("ukstub_cfg_read_fn", "ukstub_cfg_write_fn", "ukstub_range_fn", "ukstub_map_fn",
                     "usb_rd32_fn", "usb_wr32_fn", "input_irq_off_fn", "input_irq_restore_fn"), hooks):
    C.c_void_p.in_dll(lib, name).value = C.cast(cb, C.c_void_p).value


def console():
    n = u32("kstub_out_len").value
    return C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n).decode(errors="replace")


def boot(*devices):
    global sim
    sim = X.XhciSim(usb2_ports=4, usb3_ports=0)
    # the kernel stub's udelay only counts: let time pass for the device by
    # pumping after every register write the waits are made of
    write = sim.write

    def write_and_pump(a, v):
        write(a, v)
        sim.pump()
    sim.write = write_and_pump
    for i, d in enumerate(devices):
        sim.attach(i + 1, d)
    for n in ("xhci_hc_count", "usb_device_total", "usb_hid_count", "usb_hub_count", "usb_driver_count",
              "kstub_out_len", "ukstub_vmas"):
        u32(n).value = 0
    C.memset(C.addressof(C.c_uint8.in_dll(lib, "usb_k_ports")), 0, 4 * 32)
    C.c_uint64.in_dll(lib, "kstub_pages").value = (C.addressof(ARENA) + 4095) & ~4095
    cfg.clear()
    cfg[(3 << 8)] = function(0x1002, 0x164C, 0x030000, multi=True)
    cfg[XHCI] = function(0x1022, 0x1639, 0x0C0330, bar0=0xFD300004, size=1 << 20)
    lib.input_init()
    bt_init()
    usb_init()


passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def lines():
    return [l for l in console().splitlines() if l.startswith("USB:   ") or l.startswith("BT:")]


ctrl = B.HciController(hci_version=0x0B, manufacturer=89, address=bytes([0x66, 0x55, 0x44, 0x33, 0x22, 0x11]))
boot(ctrl)
check("the radio's line, then its adapter's", lines(),
      ["USB:   port 1: 1915:521f full, HCI USB (bluetooth)",
       "BT: hci0 up: HCI 5.2, manufacturer 89, address 11:22:33:44:55:66, LE"])
check("brought up during boot", ctrl.commands[0], 0x0C03)

mtk = B.HciController(vid=0x0E8D, pid=0x0608)
boot(mtk)
check("the laptop's MediaTek radio", lines(),
      ["USB:   port 1: 0e8d:0608 full, HCI USB (bluetooth)",
       "BT: hci0 needs its MediaTek firmware patch; nothing can load it at boot yet"])

bad = B.HciController(le=False)
bad.refuse[0x1009] = 0x0C
mute = B.HciController()
mute.ignore.add(0x0C03)
boot(bad, mute)
check("bring-up failures: the command and its status, or no answer", lines()[1::2],
      ["BT: hci0 did not come up: command 0x1009, status 12", "BT: hci1 did not come up: command 0x0c03, no answer"])

ctrl = B.HciController()
boot(ctrl)
sim.detach(1)
usb_poll()
check("pulled out", lines()[-2:], ["USB:   gone from port 1", "BT: hci0 gone"])
ctrl2 = B.HciController(le=False)
sim.attach(1, ctrl2)
usb_poll()
check("plugged in after boot: brought up, and its line", lines()[-2:],
      ["USB:   port 1: 1915:521f full, HCI USB (bluetooth)",
       "BT: hci1 up: HCI 5.2, manufacturer 89, address 66:55:44:33:22:11"])
ctrl2.queue(0x81, "stall")
for _ in range(3):
    sim.pump()
    usb_poll()
check("its event endpoint recovered from the USB poll", any(e[0] == "reset_ep" for e in sim.log), True)

print(f"test_bt_kernel: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

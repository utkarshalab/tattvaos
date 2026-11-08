"""The boot files (kernel/exec/bootfiles.asm): initrd.img as a UPK package,
built by boot/mkbootpkg.py and checked by the kernel's own verifier.

usage: python3 test_bootfiles.py path/to/stub.so
"""
import ctypes as C
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..", "..")
sys.path.insert(0, os.path.join(ROOT, "boot"))
import mkbootpkg as M  # noqa: E402

lib = C.CDLL(sys.argv[1])
init = lib.boot_files_init
boot_file = lib.boot_file
boot_file.restype = C.c_void_p
boot_file.argtypes = [C.c_char_p]
C.c_uint64.from_address(C.addressof(C.c_uint8.in_dll(lib, "phys_state")) + 72).value = 1 << 47
keep = []

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def console():
    n = C.c_uint32.in_dll(lib, "kstub_out_len").value
    return C.string_at(C.addressof(C.c_char.in_dll(lib, "kstub_out")), n).decode(errors="replace")


def boot(pkg, addr=None):
    """The loader's part: the package somewhere in memory, its place and
    size in the boot information."""
    info = bytearray(112)
    if pkg is not None:
        buf = C.create_string_buffer(bytes(pkg), max(len(pkg), 1))
        keep.append(buf)
        struct.pack_into("<QQ", info, 56, addr if addr is not None else C.addressof(buf), len(pkg))
    ib = C.create_string_buffer(bytes(info))
    keep.append(ib)
    C.c_uint64.in_dll(lib, "boot_info_ptr").value = C.addressof(ib)
    C.c_uint32.in_dll(lib, "kstub_out_len").value = 0
    init()
    return console()


def get(path):
    """boot_file's RAX: the file's bytes (its size, in RDX, is the entry's)."""
    return boot_file(path.encode())


def read(path, size):
    p = get(path)
    return None if not p else C.string_at(p, size)


CONF = b"# USB policy\nnew_keyboard_check = on\n"
FW = bytes((i * 7) & 0xFF for i in range(70000))
pkg = M.build([("conf/usb/usb.conf", CONF), ("app/lib/ubt/fw/mtk/bt_ram_code_mt7961_1_2_hdr.bin", FW)])

# ---- a good package ---------------------------------------------------------------------
out = boot(pkg)
check("opened and said", out, "BOOT: boot files boot 1.0.0, 2 files, unsigned\r\n")
check("ready", C.c_uint32.in_dll(lib, "boot_files_ready").value, 1)
check("a configuration file by its path", read("conf/usb/usb.conf", len(CONF)), CONF)
check("a 70 KB firmware file", read("app/lib/ubt/fw/mtk/bt_ram_code_mt7961_1_2_hdr.bin", len(FW)), FW)
check("no such file", get("conf/usb/other.conf"), None)
check("not the beginning of a path", get("conf/usb"), None)

# ---- no package, or one that cannot be used ----------------------------------------------------
check("no initrd", (boot(None), get("conf/usb/usb.conf")), ("BOOT: no boot files (no initrd.img)\r\n", None))
bad = bytearray(pkg)
bad[-100] ^= 1                                          # a byte of the firmware
check("a changed byte: refused (its SHA-256)", (boot(bad), get("conf/usb/usb.conf")),
      ("BOOT: boot files refused, error 5\r\n", None))
short = pkg[:-16]
check("cut short: refused (malformed)", boot(short), "BOOT: boot files refused, error 1\r\n")
check("not a package at all", boot(b"\x7fELF" + bytes(200)), "BOOT: boot files refused, error 1\r\n")
check("beyond the direct map: not used", boot(pkg, addr=(1 << 47) - 100), "BOOT: boot files out of reach; not used\r\n")
signed = open(os.path.join(ROOT, "kernel", "tests", "ubf", "hello.upk"), "rb").read()
check("signed by a key the kernel does not trust: refused", boot(signed), "BOOT: boot files refused, error 3\r\n")
check("a good one again after", (boot(pkg), read("conf/usb/usb.conf", len(CONF))),
      ("BOOT: boot files boot 1.0.0, 2 files, unsigned\r\n", CONF))

# ---- the builder refuses what the kernel would --------------------------------------------------
for label, files in (("an upper-case path", [("conf/USB.conf", b"x")]), ("an absolute path", [("/conf/x", b"x")]),
                     ("'..'", [("conf/../x", b"x")]), ("the same path twice", [("a", b"1"), ("a", b"2")]),
                     ("nothing", [])):
    try:
        M.build(files)
        check(f"builder: {label}", "built", "refused")
    except ValueError:
        check(f"builder: {label}", "refused", "refused")

print(f"test_bootfiles: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

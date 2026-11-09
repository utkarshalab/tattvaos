"""The HCI tables (hci/hci.def → hci/tables.asm, hci/names.asm): the
generated file current, every entry found by its code with its name,
version and layouts, codes nobody has, and every HCI constant the stack
defines by hand agreeing with hci.def.

usage: python3 test_tables.py path/to/ubt.so
"""
import ctypes as C
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
UBT = os.path.join(HERE, "..")
sys.path.insert(0, os.path.join(UBT, "hci"))
import gen_tables  # noqa: E402

lib = C.CDLL(sys.argv[1])
passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def fn(name, res, *args):
    f = getattr(lib, name)
    f.restype, f.argtypes = res, list(args)
    return f


info = {k: fn(f"ubt_hci_{k}_info", C.c_uint64, C.c_uint32) for k in ("cmd", "event", "le")}
name = fn("ubt_hci_name", C.c_char_p, C.c_uint64)
params = fn("ubt_hci_params", C.c_char_p, C.c_uint64)
returns = fn("ubt_hci_returns", C.c_char_p, C.c_uint64)
version = fn("ubt_hci_version", C.c_uint32, C.c_uint64)
DEF = os.path.join(UBT, "hci", "hci.def")
cmds, evts, les = gen_tables.parse(DEF)

check("tables.asm is what gen_tables.py makes of hci.def",
      open(os.path.join(UBT, "hci", "tables.asm"), encoding="utf-8").read(), gen_tables.generate(DEF, None))
for kind, table in (("cmd", cmds), ("event", evts), ("le", les)):
    bad = []
    for code, nm, major, minor, par, ret in table:
        e = info[kind](code)
        if not e or (name(e).decode(), version(e), params(e).decode(), returns(e).decode()) != \
                (nm, major << 8 | minor, par, ret):
            bad.append(hex(code))
    check(f"every {kind} found by its code, with its name, version and layouts ({len(table)})", bad, [])
check("codes nobody has: not found", [info["cmd"](0x0000), info["cmd"](0xFFFF), info["event"](0x9A), info["le"](0x7F)],
      [0, 0, 0, 0])
check("a few by name", [name(info["cmd"](0x0C03)), name(info["event"](0x0E)), name(info["le"](0x0D))],
      [b"RESET", b"CMD_COMPLETE", b"EXT_ADV_REPORT"])
check("versions: Inquiry 1.0, Write SSP Mode 2.1, LE Set PHY 5.0",
      [version(info["cmd"](c)) for c in (0x0401, 0x0C56, 0x2032)], [0x0100, 0x0201, 0x0500])

# ---- the stack's own constants against hci.def --------------------------------------------------------
by = {"cmd": {n: c for c, n, *_ in cmds}, "evt": {n: c for c, n, *_ in evts}, "le": {n: c for c, n, *_ in les}}
not_codes = {"COMMAND_PKT", "ACL_PKT", "SCO_PKT", "EVENT_PKT", "ISO_PKT", "FEAT_LE_BYTE", "FEAT_LE_BIT"}
seen, wrong = 0, []
for path in glob.glob(os.path.join(UBT, "**", "*.asm"), recursive=True) + glob.glob(os.path.join(UBT, "*.inc")):
    if path.endswith("tables.asm"):
        continue
    for m in re.finditer(r"^%define\s+HCI_(\w+)\s+(0x[0-9A-Fa-f]+|\d+)", open(path, encoding="utf-8").read(), re.M):
        n, v = m.group(1), int(m.group(2), 0)
        if n in not_codes:
            continue
        if n.startswith("LE_EV_"):
            kind, key = "le", n[6:]
        elif n.startswith("EV_"):
            kind, key = "evt", n[3:]
        else:
            kind, key = "cmd", n
        seen += 1
        if by[kind].get(key) != v:
            wrong.append((os.path.relpath(path, UBT), n, hex(v), hex(by[kind][key]) if key in by[kind] else None))
check(f"every hand-written HCI constant ({seen}) agrees with hci.def", wrong, [])

print(f"test_tables: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)

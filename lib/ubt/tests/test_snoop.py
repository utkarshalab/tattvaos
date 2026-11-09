"""HCI capture (snoop/snoop.asm): a btsnoop file of everything one adapter
said and heard, parsed here and compared with what the virtual controller
saw; a full buffer counting drops; capture off.

usage: python3 test_snoop.py path/to/ubt.so
"""
import ctypes as C
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l2cap_env import Env  # noqa: E402

E = Env(sys.argv[1])
check, lib = E.check, E.lib
start = E.fn("ubt_snoop_start", C.c_int32, C.c_void_p, C.c_uint64, C.c_void_p)
stop = E.fn("ubt_snoop_stop", C.c_uint64)
EPOCH_2000 = 0x00DCDDB30F2F8000


def parse(data):
    """btsnoop → (version, datalink, [(flags, drops, time, packet)])."""
    assert data[:8] == b"btsnoop\0"
    version, link = struct.unpack_from(">II", data, 8)
    out, i = [], 16
    while i < len(data):
        orig, incl, flags, drops, t = struct.unpack_from(">IIIIQ", data, i)
        out.append((flags, drops, t, data[i + 24:i + 24 + incl], orig))
        i += 24 + incl
    return version, link, out


check("too small a buffer refused", start(C.create_string_buffer(8), 8, None), -1)
buf = C.create_string_buffer(1 << 20)
check("capture of adapter A started", start(buf, len(buf), E.a), 0)
cmd_mark, acl_mark = len(E.ca.cmd_log), len(E.ca.sent)
E.now[0] = 5000
ka, kb = E.le_link()
ch = E.l2connect(ka, 0x80, 0x80, None, None)            # an LE credit request: commands and ACL
E.settle()
n = stop()
version, link, recs = parse(buf.raw[:n])
check("the file header: version 1, datalink 1002 (H4)", (version, link), (1, 1002))
cmds = [r[3][1:] for r in recs if r[0] == 2 and r[3][0] == 1]
check("every command A sent, in order, as its controller got them",
      [struct.unpack_from("<H", c)[0] for c in cmds], [c[0] for c in E.ca.cmd_log[cmd_mark:]])
check("their parameters too", [c[3:] for c in cmds], [c[1] for c in E.ca.cmd_log[cmd_mark:]])
events = [r[3] for r in recs if r[0] == 3]
check("events received, H4 type 4", (len(events) > 0, {e[0] for e in events}), (True, {4}))
check("the LE Connection Complete among them", any(e[1] == 0x3E and e[3] == 0x01 for e in events), True)
acl_out = [r[3][1:] for r in recs if r[0] == 0 and r[3][0] == 2]
check("ACL sent: exactly what the controller got, header and all", acl_out,
      [struct.pack("<HH", h | pb << 12, len(d)) + d for h, pb, d in E.ca.sent[acl_mark:]])
check("ACL received, flags 1", len([r for r in recs if r[0] == 1]) > 0, True)
check("lengths: original = included", all(r[4] == len(r[3]) for r in recs), True)
check("times from the clock, in µs since year 0", recs[0][2] - EPOCH_2000, 5000 * 1000)

# ---- only one adapter, a buffer that fills, capture off ----------------------------------------------------
small = C.create_string_buffer(16 + 40)
start(small, len(small), E.a)
E.settle()
E.l2connect(ka, 0x81, 0x80, None, None)
E.settle()
n = stop()
drops = C.c_uint32.in_dll(lib, "ubt_snoop_drops").value
check("a small buffer: what fits, the rest counted as dropped", (n <= len(small), drops > 0), (True, True))
n2 = stop()
E.l2connect(ka, 0x82, 0x80, None, None)
E.settle()
check("off: nothing more written", stop(), n2)
start(buf, len(buf), E.b)
mb = len(E.cb.cmd_log)
E.l2connect(ka, 0x83, 0x80, None, None)
E.settle()
n = stop()
recs = parse(buf.raw[:n])[2]
check("only B's packets when B is chosen", [struct.unpack_from("<H", r[3], 1)[0] for r in recs if r[0] == 2],
      [c[0] for c in E.cb.cmd_log[mb:]])

E.disconnect(ka, 0x13)
E.settle()
E.remove(E.a)
E.remove(E.b)
check("every block given back", sorted(E.live.values()), [])
print(f"test_snoop: {E.passed} passed, {E.failed} failed")
sys.exit(1 if E.failed else 0)

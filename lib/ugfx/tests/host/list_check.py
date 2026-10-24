#!/usr/bin/env python3
"""Check ugfx display lists: recording and replaying gives exactly what
drawing directly gives.

Usage: list_check.py <host_ctx binary> [--seed N]

Every ctx_check.py script runs three ways through host_ctx: drawn directly
(mode 0), recorded into a UgfxList and replayed once (mode 1), and replayed
twice (mode 2). Mode 1 must equal the direct drawing byte for byte, mode 2
must equal the script drawn directly twice over (the second copy starting
from an empty current path: recorded paths are snapshots), and scripts that fail
must fail the same way. A stress script (hundreds of records, long curved
paths) makes the list grow well past its first allocation.

Development-machine tooling only; not part of any OS image.
"""
import os
import random
import struct
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ctx_check import H, W, cases, encode  # noqa: E402


def run(tool, d, cmds, mode):
    data = encode(cmds)
    data = data[:12] + struct.pack("<I", mode) + data[16:]
    sp, raw = os.path.join(d, "l.bin"), os.path.join(d, "l.raw")
    open(sp, "wb").write(data)
    r = subprocess.run([tool, sp, raw], capture_output=True, timeout=60)
    if r.returncode:
        return None, r.returncode
    return open(raw, "rb").read(), 0


def stress(rng):
    cmds = [('stroke_style', 1.5, 4, 1, 1)]
    for i in range(300):
        cmds.append(('fill_color', rng.getrandbits(24) | 0x80000000))
        cmds.append(('fill_rect', rng.uniform(-5, W), rng.uniform(-5, H), rng.uniform(1, 12), rng.uniform(1, 9)))
    path = [('move', 2, 2)]
    for k in range(120):
        path.append(('cubic', rng.uniform(0, W), rng.uniform(0, H), rng.uniform(0, W), rng.uniform(0, H),
                     rng.uniform(0, W), rng.uniform(0, H)))
    cmds += path + [('stroke',), ('new_path',), ('rotate', 0.3)] + [('circle', 24, 16, 9), ('fill',)]
    return cmds


def main():
    tool = os.path.abspath(sys.argv[1])
    rng = random.Random(int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 1)
    failed = total = 0
    scripts = list(cases(rng)) + [("stress", stress(rng))]
    scripts += [("invalid restore", [('restore',)]), ("invalid alpha", [('alpha', 256)]),
                ("invalid dash", [('dash', 0, [0, 0]), ('rect', 1, 1, 5, 5), ('stroke',)])]
    with tempfile.TemporaryDirectory(prefix="ugfx_list.") as d:
        for name, cmds in scripts:
            total += 1
            direct, rc0 = run(tool, d, cmds, 0)
            once, rc1 = run(tool, d, cmds, 1)
            twice, rc2 = run(tool, d, cmds, 2)
            # the second pass starts from an empty current path, as the recorded paths do
            direct2, rc3 = run(tool, d, cmds + [('new_path',)] + cmds, 0)
            if name.startswith("invalid"):
                ok = rc0 == rc1 == rc2 == 5
                detail = f"exit {rc0}/{rc1}/{rc2}"
            else:
                ok = rc0 == rc1 == rc2 == rc3 == 0 and direct == once and twice == direct2
                diff = -1 if direct is None or once is None else int(np.abs(
                    np.frombuffer(direct, np.uint8).astype(int) - np.frombuffer(once, np.uint8).astype(int)).max())
                detail = f"replay==direct {direct == once} twice==direct*2 {twice == direct2} max_diff={diff}"
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'}  {name:22} {detail}")
    print(f"{total - failed}/{total} passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

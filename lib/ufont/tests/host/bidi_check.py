#!/usr/bin/env python3
"""Check lib/ufont's bidirectional algorithm against Unicode's conformance tests.

Usage: bidi_check.py <ucd directory> [host_bidi]

tools/bidi.py (the model) runs every case of BidiTest.txt (Bidi_Class
sequences, each paragraph direction the line asks for) and
BidiCharacterTest.txt (code point sequences with brackets): its levels
and visual order must be the ones given. With host_bidi (layout/bidi.asm
through tests/host/host_bidi.asm) the same cases go through ufont_bidi and
its levels and order must equal the model's.

Development-machine tooling only; not part of any OS image.
"""
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import bidi  # noqa: E402

# a representative code point per class (BidiTest.txt gives classes only)
SAMPLE = {"L": 0x61, "R": 0x5D0, "AL": 0x627, "EN": 0x31, "ES": 0x2B, "ET": 0x24, "AN": 0x660, "CS": 0x2C,
          "NSM": 0x300, "BN": 0xAD, "B": 0x2029, "S": 0x09, "WS": 0x20, "ON": 0x21, "LRE": 0x202A,
          "LRO": 0x202D, "RLE": 0x202B, "RLO": 0x202E, "PDF": 0x202C, "LRI": 0x2066, "RLI": 0x2067,
          "FSI": 0x2068, "PDI": 0x2069}


def cases(ucd):
    """-> [(code points, classes, direction, levels, order)]"""
    out = []
    levels = order = None
    for line in open(os.path.join(ucd, "BidiTest.txt"), encoding="utf-8"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        if line.startswith("@Levels:"):
            levels = [None if x == "x" else int(x) for x in line[8:].split()]
            continue
        if line.startswith("@Reorder:"):
            order = [int(x) for x in line[9:].split()]
            continue
        seq, bits = line.split(";")
        cls = seq.split()
        for bit, d in ((1, 2), (2, 0), (4, 1)):
            if int(bits) & bit:
                out.append(([SAMPLE[c] for c in cls], cls, d, levels, order))
    return out


def char_cases(ucd, bidi_class):
    out = []
    for line in open(os.path.join(ucd, "BidiCharacterTest.txt"), encoding="utf-8"):
        line = line.split("#")[0].strip()
        if not line:
            continue
        f = line.split(";")
        cps = [int(x, 16) for x in f[0].split()]
        levels = [None if x == "x" else int(x) for x in f[3].split()]
        order = [int(x) for x in f[4].split()]
        out.append((cps, [bidi_class(u) for u in cps], int(f[1]), levels, order, int(f[2])))
    return out


def run_host(tool, all_cases, d):
    """host_bidi: u32 cases, records (u32 direction, u32 count, u32 cps[]) -> (u32 para, u8 levels[] (255
    removed), u32 order count, u32 order[])."""
    inp, outp = os.path.join(d, "in.bin"), os.path.join(d, "out.bin")
    with open(inp, "wb") as f:
        f.write(struct.pack("<I", len(all_cases)))
        for cps, _, direc, *_ in all_cases:
            f.write(struct.pack("<II", direc, len(cps)) + struct.pack(f"<{len(cps)}I", *cps))
    r = subprocess.run([tool, inp, outp], capture_output=True, timeout=600)
    if r.returncode:
        return None
    data, p, res = open(outp, "rb").read(), 0, []
    for cps, *_ in all_cases:
        para, = struct.unpack_from("<I", data, p)
        p += 4
        lv = [None if x == 255 else x for x in data[p:p + len(cps)]]
        p += len(cps)
        n, = struct.unpack_from("<I", data, p)
        p += 4
        order = list(struct.unpack_from(f"<{n}I", data, p))
        p += 4 * n
        res.append((lv, order, para))
    return res


def main():
    ucd = sys.argv[1]
    tool = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else None
    bidi_class, bracket = bidi.load(ucd)
    failed = 0
    all_cases = []
    for name, cs in (("BidiTest.txt", cases(ucd)), ("BidiCharacterTest.txt", char_cases(ucd, bidi_class))):
        bad = 0
        for case in cs:
            cps, cls, direc, want_lv, want_order = case[:5]
            brackets = [bracket(u) if name != "BidiTest.txt" else None for u in cps]
            lv, para = bidi.resolve(cls, direc, brackets)
            order = bidi.reorder(lv)
            ok = lv == want_lv and order == want_order and (len(case) < 6 or para == case[5])
            if not ok:
                bad += 1
                if bad <= 3:
                    print("   ", " ".join(f"{u:04X}" for u in cps), cls, direc)
                    print("    want", want_lv, want_order)
                    print("    got ", lv, order)
            all_cases.append((cps, cls, direc, lv, order, para))
        failed += bool(bad)
        print(f"{'ok  ' if not bad else 'FAIL'}  model {name:24} {len(cs) - bad}/{len(cs)}")
    if tool:
        with tempfile.TemporaryDirectory(prefix="ufont-bidi.") as d:
            res = run_host(tool, all_cases, d)
            if res is None:
                print("FAIL  host_bidi crashed")
                failed += 1
            else:
                bad = 0
                for case, (lv, order, para) in zip(all_cases, res):
                    if (lv, order, para) != (case[3], case[4], case[5]):
                        bad += 1
                        if bad <= 3:
                            print("   ", " ".join(f"{u:04X}" for u in case[0]), case[2])
                            print("    model", case[3], case[4], case[5])
                            print("    ufont", lv, order, para)
                failed += bool(bad)
                print(f"{'ok  ' if not bad else 'FAIL'}  ufont_bidi vs model        {len(res) - bad}/{len(res)}")
    print("failed" if failed else "all passed")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()

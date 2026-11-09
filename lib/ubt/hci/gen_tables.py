"""Make lib/ubt/hci/tables.asm from lib/ubt/hci/hci.def.

usage: python3 gen_tables.py [hci.def [tables.asm]]   (defaults: beside this file)

The tables are sorted by code; every name and layout is a string ending
with 0 in one pool. hci/names.asm looks things up in them.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def parse(path):
    cmds, evts, les = [], [], []
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        kind, code, name, version, rest = line.split(None, 4)
        major, minor = (int(x) for x in version.split("."))
        params, _, ret = rest.partition("|")
        entry = (int(code, 16), name, major, minor, params.strip(), ret.strip())
        {"cmd": cmds, "evt": evts, "le": les}[kind].append(entry)
    for table in (cmds, evts, les):
        codes = [e[0] for e in table]
        assert len(codes) == len(set(codes)), "a code twice"
        table.sort()
    return cmds, evts, les


def generate(src, dst):
    cmds, evts, les = parse(src)
    pool, where = [], {}

    def at(s):
        if s not in where:
            where[s] = sum(len(p) + 1 for p in pool)
            pool.append(s)
        return where[s]

    out = ["; =============================================================================",
           "; Utkarsha OS — lib/ubt/hci/tables.asm — made by gen_tables.py from hci.def",
           "; =============================================================================",
           "; Do not edit: change hci.def and run gen_tables.py.",
           "; Each entry: code (2), major, minor, then the offsets in ubt_hci_strings of",
           "; the name, the parameters and the return parameters (4 each): 16 bytes.",
           "; =============================================================================",
           "", "%ifndef LIB_UBT_HCI_TABLES_ASM", "%define LIB_UBT_HCI_TABLES_ASM", "", "section .rodata", "align 4"]
    for label, table in (("ubt_hci_cmds", cmds), ("ubt_hci_events", evts), ("ubt_hci_le_events", les)):
        out += [f"global {label}", f"global {label}_n", f"{label}_n: dd {len(table)}", f"{label}:"]
        for code, name, major, minor, params, ret in table:
            out.append(f"    dw 0x{code:04X}\n    db {major}, {minor}\n    dd {at(name)}, {at(params)}, {at(ret)}")
    out += ["global ubt_hci_strings", "ubt_hci_strings:"]
    for s in pool:
        out.append(f'    db "{s}", 0')
    out += ["", "%endif ; LIB_UBT_HCI_TABLES_ASM", ""]
    text = "\n".join(out)
    if dst:
        open(dst, "w", encoding="utf-8", newline="\n").write(text)
    return text


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "hci.def")
    dst = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "tables.asm")
    generate(src, dst)

#!/usr/bin/env python3
"""Build initrd.img: the boot files package the kernel opens at start-up
(kernel/exec/bootfiles.asm). It is a UPK package (docs/UPK_SPEC.md) of
files the kernel needs before any disk is mounted, each under the path it
has in the system (conf/usb/usb.conf, app/lib/ubt/fw/mtk/...).

    python3 boot/mkbootpkg.py initrd.img conf/usb/usb.conf=boot/files/usb.conf

Paths are lower-case package paths; a file under conf/ is a default
configuration, any other a resource. The package is unsigned (the kernel
accepts that, as nothing checks the kernel image beside it); signing comes
with `utasm -f upk --upk-sign` once boot packages have a key.
Never overwrites an existing file.
"""
import argparse
import hashlib
import re
import struct
import sys
from pathlib import Path

MAGIC, VERSION, HEADER = 0x004B5055, 1, 144
KIND_RESOURCE, KIND_CONF = 4, 5
PART = re.compile(r"^[a-z0-9._-]+$")


def path_ok(path):
    parts = path.split("/")
    return all(p and p not in (".", "..") and PART.match(p) for p in parts)


def build(files, name="boot", version="1.0.0"):
    """files: [(package path, bytes)] → the package's bytes."""
    if not files:
        raise ValueError("a package needs at least one file")
    seen = set()
    for path, _ in files:
        if not path_ok(path):
            raise ValueError(f"not a package path: {path!r}")
        if path in seen:
            raise ValueError(f"twice: {path!r}")
        seen.add(path)
    strtab = bytearray()
    offsets = []
    for path, _ in files:
        offsets.append(len(strtab))
        strtab += path.encode() + b"\0"
    manifest = f"name = {name}\nversion = {version}\nkind = lib\ntitle = Boot files\n".encode()
    entry_off = HEADER
    str_off = entry_off + 64 * len(files)
    man_off = str_off + len(strtab)
    data_at = (man_off + len(manifest) + 15) & ~15
    entries = bytearray()
    body = bytearray()
    places = []
    for (path, data), poff in zip(files, offsets):
        here = data_at + len(body)
        places.append(here)
        kind = KIND_CONF if path.startswith("conf/") else KIND_RESOURCE
        entries += struct.pack("<IIQQ32s8s", poff, kind, here, len(data), hashlib.sha256(data).digest(), bytes(8))
        body += data
        body += bytes((-len(body)) % 16)
    total = data_at + len(body)
    # magic, version, header size, then flags, count, entry, strings,
    # string size, manifest, manifest size, reserved; file size, signer,
    # signature
    header = struct.pack("<IHH8IQ32s64s", MAGIC, VERSION, HEADER, 0, len(files),
                         entry_off, str_off, len(strtab), man_off, len(manifest), 0, total, bytes(32), bytes(64))
    assert len(header) == HEADER
    out = bytearray(header) + entries + strtab + manifest
    out += bytes(data_at - len(out))
    out += body
    assert len(out) == total
    return bytes(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    ap.add_argument("files", nargs="+", metavar="PATH=FILE")
    ap.add_argument("--version", default="1.0.0")
    args = ap.parse_args()
    files = []
    for spec in args.files:
        path, sep, source = spec.partition("=")
        if not sep:
            ap.error(f"expected PATH=FILE, got {spec!r}")
        files.append((path, Path(source).read_bytes()))
    try:
        pkg = build(files, version=args.version)
    except ValueError as e:
        ap.error(str(e))
    with args.output.open("xb") as f:
        f.write(pkg)
    print(f"{args.output}: {len(files)} files, {len(pkg)} bytes, unsigned")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Check a UBF the way the kernel's loader does (docs/UBF_SPEC.md §9), written
from the spec and sharing nothing with tools/ubfpack.py, and check the image it
came from reaches the kernel only through imports.

usage: ubf_check.py <file.ubf> <required,imports>
"""
import hashlib
import re
import struct
import subprocess
import sys

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def fnv1a(name):
    h = 0x811C9DC5
    for byte in name:
        h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
    return h


def main():
    path, required = sys.argv[1], set(sys.argv[2].split(','))
    data = open(path, 'rb').read()

    magic, version, hsize, kind, arch, flags = \
        struct.unpack_from('<IHHHHI', data, 0)
    mem_size, entry = struct.unpack_from('<QQ', data, 0x10)
    stack, seg_count, seg_off, reloc_off, reloc_count, import_off, import_count, \
        export_off, export_count, strtab_off, strtab_size, cpu, file_size = \
        struct.unpack_from('<IIIIIIIIIIIII', data, 0x20)

    check(magic == 0x00464255, 'magic')
    check(version == 1, 'version')
    check(hsize == 128, 'header size')
    check(arch == 1, 'arch')
    check(kind == 1 and flags == 1, 'an application with an entry point')
    check(file_size == len(data), 'file_size is the bytes in the file')
    check(mem_size and mem_size % 4096 == 0 and mem_size <= 1 << 30, 'mem_size')
    check(entry < mem_size, 'entry inside the image')
    check(1 <= seg_count <= 8, 'seg_count')
    check(cpu & ~0xFF == 0, 'cpu_features')
    check(data[0x54:0x58] == bytes(4) and data[0x78:0x80] == bytes(8), 'reserved')

    blank = data[:0x58] + bytes(32) + data[0x78:]
    check(hashlib.sha256(blank).digest() == data[0x58:0x78], 'sha256')

    # Tables, then segment bytes: nothing outside the file, nothing overlapping
    spans = [('header', 0, 128),
             ('segments', seg_off, seg_count * 32),
             ('relocations', reloc_off, reloc_count * 8),
             ('imports', import_off, import_count * 16),
             ('exports', export_off, export_count * 16),
             ('strings', strtab_off, strtab_size)]
    prot_of = {1: 5, 2: 1, 3: 3, 4: 3}
    segments = []
    previous_end = 0
    for i in range(seg_count):
        type_, prot, off, size, mem_off, seg_mem = \
            struct.unpack_from('<IIIIQQ', data, seg_off + i * 32)
        segments.append((type_, mem_off, seg_mem, size))
        check(prot_of.get(type_) == prot, f'segment {i} protection')
        check(prot & 6 != 6, f'segment {i} W^X')
        check(mem_off % 4096 == 0, f'segment {i} page aligned')
        check(mem_off >= previous_end, f'segment {i} order')
        check(size <= seg_mem, f'segment {i} file size')
        previous_end = mem_off + seg_mem
        if type_ == 4:
            check(size == 0, 'bss has no bytes')
        elif size:
            check(off % 16 == 0, f'segment {i} 16-byte aligned')
            spans.append((f'segment {i}', off, size))
    check(previous_end <= mem_size, 'segments inside mem_size')

    spans = sorted((s for s in spans if s[2]), key=lambda s: s[1])
    for name, off, size in spans:
        check(off + size <= len(data), f'{name} inside the file')
    for (a, off_a, size_a), (b, off_b, _) in zip(spans, spans[1:]):
        check(off_a + size_a <= off_b, f'{a} overlaps {b}')

    check(strtab_size and data[strtab_off + strtab_size - 1] == 0, 'strtab end')

    def within(offset, types):
        return any(t in types and size and
                   mem_off <= offset and offset + 8 <= mem_off + size
                   for t, mem_off, _, size in segments)

    for i in range(reloc_count):
        offset, type_ = struct.unpack_from('<II', data, reloc_off + i * 8)
        check(type_ == 1, f'relocation {i} type')
        check(within(offset, (1, 2, 3)), f'relocation {i} in file-backed bytes')

    names = {}
    for i in range(import_count):
        name_off, hash_, slot, iflags = \
            struct.unpack_from('<IIII', data, import_off + i * 16)
        check(name_off < strtab_size, f'import {i} name')
        start = strtab_off + name_off
        name = data[start:data.index(b'\0', start)]
        check(hash_ == fnv1a(name), f'import {name} hash')
        check(len(name) <= 255, f'import {name} length')
        check(iflags & ~1 == 0, f'import {name} flags')
        check(within(slot, (2,)), f'import {name} slot in rodata')
        names[name.decode()] = iflags
    strong = {n for n, f in names.items() if not f & 1}
    check(strong == required, f'required imports {sorted(strong)}')

    # Only imports reach the kernel: a syscall in the image would land in its
    # handler, which no program may rely on
    listing = subprocess.run(['objdump', '-d', '--no-show-raw-insn', path + '.elf'],
                             check=True, capture_output=True, text=True).stdout
    direct = re.findall(r'^.*\b(?:syscall|sysenter|int\s+\$0x80)\s*$', listing, re.M)
    check(not direct, f'direct kernel entry: {direct[:3]}')

    # Flipping any one byte must fail the digest
    flipped = bytearray(data)
    flipped[len(data) // 2] ^= 1
    flipped[0x58:0x78] = bytes(32)
    check(hashlib.sha256(flipped).digest() != data[0x58:0x78], 'tamper detected')

    for message in failures:
        print(f'ubf_check: FAIL {message}')
    if failures:
        sys.exit(1)
    print(f'ubf_check: {path} is valid: {mem_size} bytes loaded, {reloc_count} '
          f'relocations, {import_count} imports ({len(strong)} required)')


if __name__ == '__main__':
    main()

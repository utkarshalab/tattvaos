#!/usr/bin/env python3
"""Pack linked Canvas objects into one UBF program (docs/UBF_SPEC.md).

utasm -f ubf takes a single source; Canvas is hundreds of objects, so this
links them at image offset 0 (ubf.ld) and writes the UBF from the result:

  - .text, .rodata, .data and .bss become the four W^X segments.
  - Every 64-bit absolute address in a loaded section becomes an ABS64
    relocation. --emit-relocs keeps the list; relocations against absolute
    symbols are numbers, not addresses, and are left alone.
  - Every ut_* name the objects call and none defines becomes an import, with
    a generated stub in .text and its slot in .rodata. A name outside
    --require is weak: the kernel may not export it yet, its slot stays 0,
    and its stub returns -ENOSYS.

The linked image is kept next to the UBF as <output>.elf for its symbols.
"""
import argparse
import hashlib
import os
import struct
import subprocess
import sys

ENOSYS = 38
PAGE = 4096
MAX_MEM = 1 << 30
MAX_NAME = 255

HEADER_SIZE = 128
KIND_APP = 1
ARCH_X86_64 = 1
FLAG_ENTRY = 1
IMPORT_WEAK = 1
REL_ABS64 = 1

PROT_R, PROT_W, PROT_X = 1, 2, 4
SEGMENTS = (                            # section, UBF type, protection
    ('.text', 1, PROT_R | PROT_X),
    ('.rodata', 2, PROT_R),
    ('.data', 3, PROT_R | PROT_W),
    ('.bss', 4, PROT_R | PROT_W),
)

R_X86_64_64 = 1
R_PC_RELATIVE = {2, 4, 13, 15, 24}      # PC32, PLT32, PC16, PC8, PC64: the
                                        # image moves as a whole, so these hold
SHT_SYMTAB, SHT_RELA, SHT_NOBITS = 2, 4, 8
SHF_ALLOC = 2
SHN_ABS = 0xFFF1

SLOTS_SYMBOL = '__ubf_slots'


def die(message):
    sys.exit(f'ubfpack: {message}')


def fnv1a(name):
    h = 0x811C9DC5
    for byte in name.encode():
        h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
    return h


def align(value, to):
    return (value + to - 1) & -to


def undefined_services(objects):
    """The ut_* names the objects use and do not define, sorted."""
    def names(*flags):
        out = subprocess.run(['nm', *flags, *objects], check=True,
                             capture_output=True, text=True).stdout
        return {line.split()[-1] for line in out.splitlines()
                if line.strip() and not line.endswith(':')}
    return sorted(n for n in names('-u') - names('--defined-only')
                  if n.startswith('ut_'))


def write_imports(path, names):
    """The stubs and slots, as assembly."""
    lines = ['default rel', 'section .text', '__ubf_missing:',
             f'    mov rax, -{ENOSYS}', '    ret']
    for i, name in enumerate(names):
        lines += [f'global {name}', f'{name}:',
                  f'    mov rax, [{SLOTS_SYMBOL} + {i * 8}]',
                  '    test rax, rax', '    jz __ubf_missing', '    jmp rax']
    lines += ['section .rodata align=8', f'global {SLOTS_SYMBOL}',
              f'{SLOTS_SYMBOL}:', f'    times {len(names)} dq 0']
    with open(path, 'w') as f:
        f.write('\n'.join(lines) + '\n')


class Elf:
    def __init__(self, path):
        self.data = data = open(path, 'rb').read()
        shoff, = struct.unpack_from('<Q', data, 0x28)
        shentsize, shnum, shstrndx = struct.unpack_from('<HHH', data, 0x3A)
        self.sections = []
        for i in range(shnum):
            name, type_, flags, addr, off, size, link, info, addralign, _ = \
                struct.unpack_from('<IIQQQQIIQQ', data, shoff + i * shentsize)
            self.sections.append(dict(name=name, type=type_, flags=flags,
                                      addr=addr, off=off, size=size, link=link,
                                      info=info, align=addralign))
        strings = self.sections[shstrndx]
        for s in self.sections:
            s['name'] = self.string(strings, s['name'])

    def string(self, table, offset):
        start = table['off'] + offset
        return self.data[start:self.data.index(b'\0', start)].decode()

    def section(self, name):
        return next((s for s in self.sections if s['name'] == name), None)

    def symbols(self, table):
        """(name, shndx, value) of every entry in a symbol table."""
        strings = self.sections[table['link']]
        out = []
        for off in range(table['off'], table['off'] + table['size'], 24):
            name, _, _, shndx, value, _ = \
                struct.unpack_from('<IBBHQQ', self.data, off)
            out.append((self.string(strings, name), shndx, value))
        return out

    def symbol(self, name):
        table = next(s for s in self.sections if s['type'] == SHT_SYMTAB)
        for sym_name, _, value in self.symbols(table):
            if sym_name == name:
                return value
        die(f'no symbol {name} in the linked image')


def collect_segments(elf):
    """(type, prot, section) of each non-empty segment, checking nothing else
    was linked into the image."""
    known = {name for name, _, _ in SEGMENTS}
    for s in elf.sections:
        if s['flags'] & SHF_ALLOC and s['name'] not in known and s['size']:
            die(f'loaded section {s["name"]} has no UBF segment')
    segments = []
    for name, type_, prot in SEGMENTS:
        s = elf.section(name)
        if s is None or s['size'] == 0:
            continue
        if s['align'] > PAGE or s['addr'] % PAGE:
            die(f'{name} is not page aligned at {s["addr"]:#x}, '
                f'alignment {s["align"]}')
        segments.append((type_, prot, s))
    return segments


def collect_relocations(elf, segments):
    """Image offsets of the 64-bit fields that hold an address, sorted."""
    def field(offset):
        for type_, _, s in segments:
            if s['addr'] <= offset and offset + 8 <= s['addr'] + s['size']:
                if type_ == 4:
                    break
                return struct.unpack_from('<Q', elf.data,
                                          s['off'] + offset - s['addr'])[0]
        die(f'relocated field {offset:#x} is not inside a segment with bytes')

    offsets = []
    for rela in elf.sections:
        if rela['type'] != SHT_RELA or \
                not elf.sections[rela['info']]['flags'] & SHF_ALLOC:
            continue
        symbols = elf.symbols(elf.sections[rela['link']])
        for off in range(rela['off'], rela['off'] + rela['size'], 24):
            offset, info, addend = struct.unpack_from('<QQq', elf.data, off)
            kind, index = info & 0xFFFFFFFF, info >> 32
            name, shndx, value = symbols[index]
            if kind in R_PC_RELATIVE:
                continue
            if shndx == SHN_ABS:
                continue
            if kind != R_X86_64_64:
                die(f'relocation type {kind} against {name or "a section"} '
                    f'at {offset:#x} cannot be expressed in UBF')
            if field(offset) != value + addend:
                die(f'field {offset:#x} does not hold {name or "its target"}')
            offsets.append(offset)
    return sorted(offsets)


def pack(elf, names, required, entry, stack):
    segments = collect_segments(elf)
    relocations = collect_relocations(elf, segments)
    slots = elf.symbol(SLOTS_SYMBOL)

    last = segments[-1][2]
    mem_size = align(last['addr'] + last['size'], PAGE)
    if mem_size > MAX_MEM:
        die(f'{mem_size} bytes is more than a UBF may occupy')

    strtab = bytearray()
    imports = bytearray()
    for i, name in enumerate(names):
        if len(name) > MAX_NAME:
            die(f'{name} is too long for an import')
        imports += struct.pack('<IIII', len(strtab), fnv1a(name), slots + i * 8,
                               0 if name in required else IMPORT_WEAK)
        strtab += name.encode() + b'\0'

    seg_off = HEADER_SIZE
    reloc_off = seg_off + 32 * len(segments)
    import_off = reloc_off + 8 * len(relocations)
    export_off = import_off + len(imports)
    strtab_off = export_off
    body_start = align(strtab_off + len(strtab), 16)

    table = bytearray()
    contents = bytearray()
    for type_, prot, s in segments:
        stored = 0 if s['type'] == SHT_NOBITS else s['size']
        file_off = body_start + len(contents) if stored else 0
        table += struct.pack('<IIIIQQ', type_, prot, file_off, stored,
                             s['addr'], s['size'])
        contents += elf.data[s['off']:s['off'] + stored]
        contents += bytes(-len(contents) % 16)
    file_size = body_start + len(contents)

    header = bytearray(HEADER_SIZE)
    struct.pack_into('<IHHHHI', header, 0, 0x00464255, 1, HEADER_SIZE, KIND_APP,
                     ARCH_X86_64, FLAG_ENTRY)
    struct.pack_into('<QQ', header, 0x10, mem_size, entry)
    struct.pack_into('<IIIIIIIIIIIII', header, 0x20, stack, len(segments),
                     seg_off, reloc_off, len(relocations), import_off,
                     len(names), export_off, 0, strtab_off, len(strtab), 0,
                     file_size)

    image = header + table
    image += b''.join(struct.pack('<II', r, REL_ABS64) for r in relocations)
    image += imports + strtab
    image += bytes(body_start - len(image))
    image += contents
    image[0x58:0x78] = hashlib.sha256(image).digest()
    return bytes(image), len(relocations)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    parser.add_argument('-o', '--output', required=True)
    parser.add_argument('--script', required=True, help='the link script')
    parser.add_argument('--entry', required=True, help='the entry symbol')
    parser.add_argument('--stack', type=int, default=0,
                        help='fiber stack in bytes; 0 is the system default')
    parser.add_argument('--require', default='',
                        help='comma-separated imports that must resolve')
    parser.add_argument('objects', nargs='+')
    args = parser.parse_args()

    names = undefined_services(args.objects)
    required = {n for n in args.require.split(',') if n}
    missing = required - set(names)
    if missing:
        die(f'nothing calls {", ".join(sorted(missing))}: --require is stale')

    os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)
    source = args.output + '.imports.asm'
    stubs = args.output + '.imports.o'
    linked = args.output + '.elf'
    write_imports(source, names)
    subprocess.run(['nasm', '-f', 'elf64', '-o', stubs, source], check=True)
    subprocess.run(['ld', '-nostdlib', '-static', '-z', 'max-page-size=0x1000',
                    '--build-id=none', '--emit-relocs', '-T', args.script,
                    '-e', args.entry, '-o', linked, *args.objects, stubs],
                   check=True)

    elf = Elf(linked)
    image, relocations = pack(elf, names, required, elf.symbol(args.entry),
                              args.stack)
    with open(args.output, 'wb') as f:
        f.write(image)
    print(f'  UBF    {args.output}: {len(image)} bytes, {relocations} '
          f'relocations, {len(names)} imports ({len(required)} required)')


if __name__ == '__main__':
    main()

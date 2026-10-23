# Utkarsha Binary Format (UBF)

> The on-disk format of every program Utkarsha OS runs outside the kernel
> image: applications (`app/<app>/main`), commands (`app/cmd/<command>`) and
> shared libraries (`app/lib/<lib>/`). Built by `utasm -f ubf`, loaded by the
> kernel's program loader, shipped inside UPK packages ([UPK_SPEC.md](UPK_SPEC.md)).

**Status:** version 1, draft. The kernel image itself is ULF, and boot images
are UBI; both are separate formats.

## Contents

1. [Model](#1-model)
2. [File layout](#2-file-layout)
3. [Header](#3-header)
4. [Segments](#4-segments)
5. [Relocations](#5-relocations)
6. [Imports](#6-imports)
7. [Exports](#7-exports)
8. [Entry contract](#8-entry-contract)
9. [Loading](#9-loading)
10. [Producing UBF with utasm](#10-producing-ubf-with-utasm)
11. [Limits and reserved values](#11-limits-and-reserved-values)

---

## 1. Model

Utkarsha OS runs every task in one address space at one privilege level, so a
program is not given an address space of its own: the loader places it
wherever free memory is, and protection comes from page permissions and from
`usrauth`, not from separation. That fixes four properties of the format.

1. **Relocatable.** Code reaches its own data RIP-relative. The only fix-up is
   adding the load address to a 64-bit absolute pointer (§5).
2. **W^X.** Code, read-only data, writable data and zero-filled data are
   separate, page-aligned segments; no page is ever writable and executable.
3. **Named imports.** A program reaches kernel and library services by name.
   The loader resolves each name against the published exports and writes the
   address into the program's import table (§6).
4. **Integrity.** The header carries a SHA-256 of the whole file. Authenticity
   (who built it) is the package's job: a UPK signs the digests of the files
   it carries.

All multi-byte fields are little-endian. "Offset" means an offset into the
file; "image offset" means an offset from the load address in memory.

## 2. File layout

```
+---------------------------+  0
| header (128 bytes)        |
+---------------------------+  seg_table_off
| segment table             |  seg_count x 32 bytes
+---------------------------+  reloc_off
| relocation table          |  reloc_count x 8 bytes
+---------------------------+  import_off
| import table              |  import_count x 16 bytes
+---------------------------+  export_off
| export table              |  export_count x 16 bytes
+---------------------------+  strtab_off
| string table              |  strtab_size bytes, NUL-terminated names
+---------------------------+  (16-byte aligned)
| segment contents          |  each segment's file bytes, at its file_off
+---------------------------+  file_size
```

Tables may appear in any order after the header, but none may overlap another
table, a segment's file bytes or the header, and all must lie inside
`file_size`.

## 3. Header

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `magic` | `"UBF\0"` = `0x00464255` |
| 0x04 | 2 | `version` | 1 |
| 0x06 | 2 | `header_size` | 128 |
| 0x08 | 2 | `kind` | 1 application, 2 library, 3 command |
| 0x0A | 2 | `arch` | 1 x86-64 (2 AArch64, 3 RISC-V 64 reserved) |
| 0x0C | 4 | `flags` | bit 0: has an entry point; others 0 |
| 0x10 | 8 | `mem_size` | bytes the loaded image occupies; a multiple of 4096 |
| 0x18 | 8 | `entry` | image offset of the entry point (§8); 0 when flag bit 0 is clear |
| 0x20 | 4 | `stack_size` | fiber stack the program asks for, bytes; 0 = system default |
| 0x24 | 4 | `seg_count` | 1–8 |
| 0x28 | 4 | `seg_table_off` | |
| 0x2C | 4 | `reloc_off` | |
| 0x30 | 4 | `reloc_count` | |
| 0x34 | 4 | `import_off` | |
| 0x38 | 4 | `import_count` | |
| 0x3C | 4 | `export_off` | |
| 0x40 | 4 | `export_count` | |
| 0x44 | 4 | `strtab_off` | |
| 0x48 | 4 | `strtab_size` | |
| 0x4C | 4 | `cpu_features` | CPU features the code needs (§11); the loader refuses the file on a CPU without them |
| 0x50 | 4 | `file_size` | total file length |
| 0x54 | 4 | reserved | 0 |
| 0x58 | 32 | `sha256` | SHA-256 of the whole file, computed with this field zero |
| 0x78 | 8 | reserved | 0 |

## 4. Segments

Segment entry (32 bytes):

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `type` | 1 text, 2 rodata, 3 data, 4 bss |
| 0x04 | 4 | `prot` | bit 0 read, bit 1 write, bit 2 execute |
| 0x08 | 4 | `file_off` | where the segment's bytes start (0 for bss) |
| 0x0C | 4 | `file_size` | bytes stored in the file (0 for bss) |
| 0x10 | 8 | `mem_off` | image offset; a multiple of 4096 |
| 0x18 | 8 | `mem_size` | bytes in memory, ≥ `file_size`; the rest is zero-filled |

Rules the loader enforces:

- Segments are in increasing `mem_off` order and do not overlap; each ends at
  or before the next one's `mem_off`, and the last ends at or before
  `mem_size`.
- `prot` matches the type: text `R|X`, rodata `R`, data and bss `R|W`. No
  segment is ever `W|X`.
- A bss segment has `file_size` 0.

The import table's slots (§6) live in a rodata segment: the loader writes
them before it applies the final page permissions, so after loading they are
read-only and cannot be redirected.

## 5. Relocations

Relocation entry (8 bytes):

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `offset` | image offset of the field to fix |
| 0x04 | 4 | `type` | 1 `ABS64`: add the load address to the 64-bit field |

`ABS64` is the only type. Every field it names lies wholly inside a segment
that has file bytes (not bss). Position-dependent forms a relocatable image
cannot express — 32-bit absolute addresses, for example — are rejected by
utasm at build time, not patched at load time.

## 6. Imports

Import entry (16 bytes):

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `name_off` | offset of the name in the string table |
| 0x04 | 4 | `hash` | FNV-1a 32-bit hash of the name, for lookup |
| 0x08 | 4 | `slot` | image offset of the 8-byte slot that receives the address |
| 0x0C | 4 | `flags` | bit 0 weak: if unresolved, write 0 instead of refusing to load |

A name is resolved, in order, against the kernel's export table and the
export tables of the libraries the program's package depends on. Two
providers of one name is an error at load time, not a silent pick.

Code calls an import through its slot (`call [rel slot]`). utasm generates
this for an `extern` function, so source code writes an ordinary
`call io_fd_alloc` (§10).

## 7. Exports

Export entry (16 bytes):

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0x00 | 4 | `name_off` | offset of the name in the string table |
| 0x04 | 4 | `hash` | FNV-1a 32-bit hash of the name |
| 0x08 | 8 | `offset` | image offset of the symbol |

Libraries export what other programs may import. An application may export
symbols too (for plug-ins); the loader publishes a program's exports only
when its package says so.

## 8. Entry contract

The loader starts an application or command as a new fiber at
`load address + entry`, with:

- `RDI` = pointer to the program's start block (arguments, the caller's
  working folder, standard handles; layout in `kernel/exec/`),
- `RSP` 16-byte aligned, minus 8, as after a `call`,
- the System V AMD64 calling convention for everything else.

Returning from the entry point ends the program; `EAX` is its exit status.
A library has no entry point (flag bit 0 clear).

## 9. Loading

The loader rejects a file, before running any of it, unless every check
passes:

1. `magic`, `version`, `header_size`, `arch`, and `file_size` equal to the
   bytes actually read.
2. The SHA-256 matches.
3. Every table and segment lies inside the file and the image, as §2–§5
   require; counts are within §11's limits.
4. Every `cpu_features` bit is present on this CPU.

Then it:

1. reserves `mem_size` bytes, page-aligned, writable and not executable;
2. copies each segment's file bytes to `load + mem_off` and zero-fills the
   rest of its `mem_size`;
3. applies every relocation;
4. resolves every import and writes its slot, failing on an unresolved
   non-weak name;
5. sets each segment's pages to its `prot`;
6. for an application or command, starts the entry fiber; for a library,
   publishes its exports.

## 10. Producing UBF with utasm

```sh
utasm -f ubf app.s -o main
```

- `section .text`, `.rodata`, `.data` and `.bss` become the four segments.
  utasm puts its import slots and call stubs in rodata and text.
- `extern name` declares an import. A `call name` or `jmp name` to it goes
  through a six-byte stub `jmp [rel slot]` that utasm adds to the text
  segment. Reading an imported variable directly is not supported in
  version 1; export an accessor function instead.
- `global name` exports a symbol.
- Absolute 64-bit uses of a label (`dq label`, `mov rax, label`) become
  `ABS64` relocations. Any other absolute form is an error, so `default rel`
  is assumed.
- The entry point is `_start`, or `main` when there is no `_start`.

## 11. Limits and reserved values

| Item | Limit |
|---|---|
| `seg_count` | 8 |
| `import_count`, `export_count` | 65 535 each |
| name length | 255 bytes, excluding the NUL |
| `mem_size` | 1 GiB |

`cpu_features` bits:

| Bit | Feature |
|---|---|
| 0 | SSE4.2 |
| 1 | AVX |
| 2 | AVX2 |
| 3 | BMI1 + BMI2 |
| 4 | AVX-512F |
| 5 | AVX-512BW |
| 6 | AES-NI |
| 7 | SHA extensions |
| 8–31 | reserved, 0 |

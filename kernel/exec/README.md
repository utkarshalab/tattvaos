# kernel/exec — running programs

> The program loader: a UBF file ([docs/UBF_SPEC.md](../../docs/UBF_SPEC.md))
> becomes a mapped, relocated program, started as a fiber.

| File | What is in it |
|---|---|
| [`ubf.inc`](ubf.inc) | the UBF layout, the loaded-program record (`ubf_prog_t`), the export entry, the errors, the program window |
| [`ubf_load.asm`](ubf_load.asm) | `ubf_load`, `ubf_start`, `ubf_cpu_features` |
| [`exports.asm`](exports.asm) | what the kernel exports to programs (`UBF_EXPORT`), `ubf_export_find` |
| [`selftest.asm`](selftest.asm) | the boot self-test: loads, runs and checks [`kernel/tests/ubf/hello.ubf`](../tests/ubf/), and refuses a tampered copy |
| [`exec.asm`](exec.asm) | the one include `kernel/entry.asm` needs |

## Loading

`ubf_load(file, length, record)` checks the whole file before it touches
memory: the header, every table's bounds, the SHA-256, the CPU features the
program needs, the segments (page-aligned, in order, never writable and
executable), every relocation, import and export. Then it:

1. allocates `mem_size` bytes of physical pages and a place in the program
   window (1 TiB – 2 TiB, an unmapped guard page after each program);
2. zeroes the pages and copies each segment's bytes, through the identity
   mapping;
3. adds the window address to every `ABS64` field;
4. resolves each import against the kernel's exports and writes its slot;
5. maps each segment's pages into the window with its own permissions:
   text read + execute, rodata read only, data and bss read + write.

Programs are mapped with 4 KiB pages so each segment gets exactly its own
permissions, without touching the identity map's large pages.

`ubf_start(record, start_block)` starts an application's entry point as a
fiber, with the start block in `RDI`.

## Exports

A program reaches the kernel through named imports. The kernel's exports are
one `UBF_EXPORT "name", symbol` line each in [`exports.asm`](exports.asm);
the name's FNV-1a hash is computed when the kernel is assembled. Today:

| Name | What it does |
|---|---|
| `ut_console_print` | writes a NUL-terminated string (`RDI`) to the console |
| `ut_yield` | lets the other ready fibers run |

## Not yet

- Exports of loaded libraries (`app/lib/`) are recorded but not yet
  published for other programs to import.
- A failure while mapping leaves the pages already mapped in place.
- Programs are loaded from memory; reading them from `app/` comes with the
  filesystem.

Part of the `kernel/` category in Utkarsha OS.

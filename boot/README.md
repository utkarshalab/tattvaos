# TattvaOS boot paths

The boot layer currently has two x86-64 paths:

- legacy BIOS: stage1 -> stage2 -> ULF v2 kernel;
- UEFI: PE32+ loader -> firmware-owned ULF backing -> owned x86-64
  transition -> the same kernel entry point.

## Build and validate

```sh
make -C boot img
make -C boot uefi
make -C boot uefi-check
make -C boot ovmf-test
make -C boot ovmf-strictnx-test
make -C boot test
```

`BOOTX64.EFI` is a generated artifact. The OVMF test constructs a temporary
virtual ESP, boots the real PE image and `kernel.ulf`, and requires ordered
UART milestones through the first scheduler heartbeat. The strict-NX target
uses OVMF's stronger firmware memory protections when that image is installed.

## UEFI ownership contract

The UEFI loader:

1. validates ULF v2 metadata before allocating from untrusted sizes;
2. allocates and zeroes the complete page-rounded memory footprint below
   4 GiB, then reads and checksums the exact initialized image;
3. keeps the kernel linked at virtual 1 MiB while mapping arbitrary
   firmware-owned physical backing there;
4. maps the executable prefix read-only/executable and the remainder
   read/write/non-executable when NX is available, with no writable physical
   alias for non-identity kernel backing;
5. owns and verifies its transition CR3, GDT, IDT, BootInfo/E820 storage, and
   stack before the final memory-map window;
6. acquires a bounded, firmware-sized raw memory map and canonicalizes
   descriptors in physical order without trusting firmware ordering;
7. exits boot services with one bounded stale-key retry, normalizes CPU state,
   and enters only the validated ULF entry.

Native tests mutate the transition arena, validate ULF and memory-map bounds,
exercise short file reads and TCG2 calls, and inspect linked PE entry/section
permissions. OVMF is the end-to-end gate.

## Current boundaries

This is an x86-64 bootstrap, not yet a blanket bare-metal certification. The
initial physical aperture is the low 4 GiB, the UEFI path starts one BSP, and
UEFI panic recovery is not implemented. Platform matrices, AP startup, IOMMU
policy, Secure Boot signing, and broad firmware interoperability remain later
hardening phases.

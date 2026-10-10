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
make -C boot smp-check
make -C boot smp-test
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
5. owns and verifies its transition CR3, GDT, IDT, BootInfo/E820 storage,
   stack, and low SIPI page before the final memory-map window;
6. acquires a bounded, firmware-sized raw memory map and canonicalizes
   descriptors in physical order without trusting firmware ordering;
7. exits boot services with one bounded stale-key retry, normalizes CPU state,
   and enters only the validated ULF entry.

Native tests mutate the transition arena, validate ULF and memory-map bounds,
exercise short file reads and TCG2 calls, and inspect linked PE entry/section
permissions. OVMF is the end-to-end gate.

## Kernel-owned SMP contract

Both loaders publish one reserved 4 KiB SIPI page through the versioned
112-byte BootInfo ABI and enter the kernel with only the BSP online. The
kernel validates RSDP -> XSDT/RSDT -> MADT, accepts enabled APIC/x2APIC
processors up to the 64-core per-CPU bound, builds private stack/GDT/TSS/IST
state, seals the copied trampoline read-only/executable, and performs targeted
INIT/SIPI rendezvous. APs remain behind a release barrier until shared
initialization and initial fiber creation finish.

Startup is deliberately all-or-nothing: an AP timeout or feature mismatch
atomically cancels the rendezvous and keeps the system BSP-only, avoiding
sparse logical CPU IDs. TLB, decompression, and ACPI self-IPI paths use the
active xAPIC/x2APIC backend. When every processor advertises x2APIC, the
kernel switches the BSP before startup unless a validated Intel DMAR table
opts the platform out; malformed DMAR also prevents a new transition. Each AP
joins the selected mode before programming its LVT. Every released processor
then runs a kernel-owned 10 ms local timer: invariant TSC-deadline when
available, otherwise a per-core TSC-calibrated periodic APIC timer. Boot does
not proceed until every timer has delivered at least two interrupts. The
smp-test target boots the real BIOS and OVMF paths
with 2 and 8 processors in x2APIC mode, exercises an xAPIC fallback, and
requires exact mode/discovery/rendezvous/online/post-barrier markers.

## Current boundaries

This is an x86-64 bootstrap, not yet a blanket bare-metal certification. The
initial physical aperture is the low 4 GiB, CPU topology is static after boot,
and UEFI panic recovery is not implemented. The startup path does not yet
online more than 64 CPUs. Device interrupt delivery to wide x2APIC IDs still
requires IOMMU interrupt remapping; current devices remain polling/BSP-routed.
IOMMU policy, Secure Boot signing, CPU/memory hotplug, and broad firmware
interoperability remain later hardening phases.

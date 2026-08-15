# lib/hw/ucxl — CXL Device Enumeration

> Real CXL memory device discovery for Tattva OS, via PCI class code.

| File | Covers |
|---|---|
| [`cxl.asm`](cxl.asm) | PCI class 0x05/subclass 0x02 (CXL Type 3 Memory Device) scan, reusing `hw_pci_cfg_read32` from `lib/hw/ugpu/detect.asm` |

## Why this exists next to lib/mem/virt/cxl

`lib/mem/virt/cxl/cxl_t1.asm` already exists, but it has no discovery
behind it: `cxl_t1_init` unconditionally sets a hardcoded bandwidth
constant (64000 MB/s, "PCIe Gen5 x16") and an active flag, regardless of
what hardware is actually present. `cxl.asm` is the missing step — real
PCI identity for whatever CXL memory devices actually exist.

## Scope limit: no DVSEC, no Type 1/2

The real CXL device breakdown lives in the CXL DVSEC (Designated
Vendor-Specific Extended Capability, vendor ID `0x1E98`) in PCIe Extended
Configuration Space — offset ≥ 0x100. The legacy CF8/CFC mechanism
`hw_pci_cfg_read32` uses only reaches the first 256 bytes; getting to
extended space needs ECAM (MMIO-based, from the ACPI MCFG table), which
`lib/io/acpi/mcfg.asm` implements but isn't wired into the kernel
translation unit yet (see `lib/hw/ugpu/README.md` for the same
lib/io-isn't-wired-in constraint on the GPU side).

That also means this only catches **CXL Type 3** (memory expander)
devices — they're the ones with a distinguishing class code. Type 1/2
accelerators don't get one; only the DVSEC tells them apart, which is
exactly what's out of reach here. Once ECAM is available, the DVSEC walk
is the natural extension point for both gaps.

Part of the `lib/` category in Tattva OS.

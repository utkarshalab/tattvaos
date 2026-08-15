# lib/hw — Hardware Topology & Locality

> Direct hardware access and topology discovery for Tattva OS.
> No HAL. No driver model. Direct register access where possible.

| Subsystem | Covers |
|---|---|
| [`ucpu/`](ucpu/) | CPU topology (CPUID leaf 0x1F/0x0B), cache hierarchy, MTRR/PAT cache-policy control, SMT/LLC-domain pinning queries |
| [`unuma/`](unuma/) | Real SRAT-derived CPU-to-NUMA-node mapping and current-core locality checks |
| [`ugpu/`](ugpu/) | PCI GPU inventory, PCIe link bandwidth, NVIDIA-vendor capability signal |
| [`uhbm/`](uhbm/) | ACPI HMAT bandwidth-tier memory (HBM vs. DDR) |
| [`ucxl/`](ucxl/) | PCI CXL memory device enumeration |
| [`uhwloc/`](uhwloc/) | Combined queries over all of the above |

## Layering

`ucpu` and `unuma`'s ACPI/CPUID parsing are self-contained. `ugpu` and
`ucxl` share one PCI config-space primitive (`hw_pci_cfg_read32`, defined
in `ugpu/detect.asm`) rather than each reimplementing CF8/CFC. `uhwloc`
depends on every other subsystem and was built last for that reason.

Three subsystems reuse ACPI tables `lib/mem/numa/numa_detect.asm` already
locates during its own RSDP → XSDT/RSDT walk (`numa_srat_phys_addr` /
`numa_hmat_phys_addr`) instead of re-walking those tables themselves —
`unuma` for SRAT, `uhbm` for HMAT. `unuma`, `ugpu`, and `ucxl` must
therefore run after `numa_detect_init`.

## What this deliberately doesn't cover

- **PCI enumeration/BAR mapping/DMA at large**: `lib/io/pci` and
  `lib/io/dma` already implement this more fully, but `lib/io/io.asm`
  (the aggregator that would pull them into the kernel translation unit)
  isn't wired into `kernel/entry.asm` yet — wiring in the rest of
  `lib/io` is a separate, larger step, not a side effect of this tree.
  `ugpu`/`ucxl` use their own minimal reader instead of depending on code
  that isn't in the build.
- **PCIe Extended Config Space** (offset ≥ 0x100): needs ECAM/MCFG, same
  reason as above. This is why `ucxl` can't walk the CXL DVSEC.
- **GPU/CXL-to-NUMA-node locality**: needs an ACPI AML interpreter to
  evaluate each PCI device's `_PXM` object — out of scope for the
  fixed-table parsers here.
- **NVLink topology**: proprietary NVIDIA MMIO layout with no public
  documentation to parse against.

Part of the `lib/` category in Tattva OS.

# lib/hw/ugpu — GPU Hardware Layer

> GPU inventory, PCIe link bandwidth, and NVLink capability signal for
> Tattva OS.

| File | Covers |
|---|---|
| [`detect.asm`](detect.asm) | PCI class 0x03 (Display Controller) scan; also defines `hw_pci_cfg_read32`, the shared CF8/CFC config-space reader `ucxl/cxl.asm` reuses |
| [`pcie.asm`](pcie.asm) | Effective link bandwidth (MB/s) from the PCIe Capability's Link Status register |
| [`nvlink.asm`](nvlink.asm) | NVIDIA-vendor capability signal (see scope note below) |

## Why a self-contained PCI reader

`lib/io/pci/*.asm` already implements PCI enumeration, BAR mapping, and
link verification — but `lib/io/io.asm`, the file that aggregates it into
one includable unit, is not wired into `kernel/entry.asm` yet (only
`lib/hw/ucpu/{mtrr,pat}.asm` reaches the kernel translation unit from the
`hw/` tree so far). Wiring in the rest of `lib/io` is a separate, larger
step — it pulls in NVMe/virtio-blk/DMA/interrupts along with it — not a
side effect of building out `lib/hw`. `detect.asm` therefore implements
its own minimal CF8/CFC reader (`hw_pci_cfg_read32`) rather than depending
on code that isn't in the build.

## NVLink scope note

`nvlink.asm` can only report NVIDIA-vendor PCI IDs — necessary but not
sufficient for NVLink. The real link topology (which GPUs are connected,
link count, per-link speed) lives behind NVIDIA's proprietary MMIO layout,
not a public PCIe capability the way link speed/width is for `pcie.asm`.
That's the same tradeoff `lib/mem/virt/cxl/cxl_t1.asm` makes for CXL (a
flag + a constant, not a real protocol walk); going further needs the
vendor spec, not more guessing here.

Part of the `lib/` category in Tattva OS.

%ifndef GUARD_STORAGE_UXFS_DRIVERS_DRIVERS_ASM
%define GUARD_STORAGE_UXFS_DRIVERS_DRIVERS_ASM
; =============================================================================
; Utkarsha OS — lib/storage/uxfs/drivers/drivers.asm
; =============================================================================
; Master Storage Hardware Driver Dispatcher & Module Aggregator.
;
; Aggregates all UXFS hardware storage controller drivers:
;   - NVMe PCIe SSD driver (`nvme.asm`)
;   - NVMe Zoned Namespaces driver (`nvme_zns.asm`)
;   - USB Mass Storage driver (`usb_storage.asm`)
;   - AHCI SATA Controller driver (`ahci.asm`)
;   - SDHCI SD Card Controller driver (`sdhci.asm`)
;   - VirtIO Block Device driver (`virtio_blk.asm`)
;   - NVMe-over-Fabrics Network driver (`nvme_of.asm`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/storage/uxfs/drivers/nvme.asm"
%include "lib/storage/uxfs/drivers/nvme_zns.asm"
%include "lib/storage/uxfs/drivers/usb_storage.asm"
%include "lib/storage/uxfs/drivers/ahci.asm"
%include "lib/storage/uxfs/drivers/sdhci.asm"
%include "lib/storage/uxfs/drivers/virtio_blk.asm"
%include "lib/storage/uxfs/drivers/nvme_of.asm"

%endif ; GUARD_STORAGE_UXFS_DRIVERS_DRIVERS_ASM

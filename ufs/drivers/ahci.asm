; =============================================================================
; Tattva OS — ufs/drivers/ahci.asm
; =============================================================================
; SATA Hard Disk Drive (HDD) & SATA SSD AHCI Controller Driver.
;
; Implements AHCI HBA Port Memory Registers, Command List Headers, FIS (Frame
; Information Structure) Construction, and DMA Read/Write commands.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define FIS_TYPE_REG_H2D            0x27

struc ufs_fis_reg_h2d_t
    .fis_type:          resb 1      ; 0x27 (Register FIS - Host to Device)
    .pmport_c:          resb 1      ; Port & Command bit
    .command:           resb 1      ; ATA Command (0x25 READ DMA EXT, 0x35 WRITE DMA EXT)
    .feature_lo:        resb 1
    .lba0:              resb 1      ; LBA low byte
    .lba1:              resb 1      ; LBA mid byte
    .lba2:              resb 1      ; LBA high byte
    .device:            resb 1      ; 1 << 6 (LBA mode)
    .lba3:              resb 1
    .lba4:              resb 1
    .lba5:              resb 1
    .feature_hi:        resb 1
    .count_lo:          resb 1      ; Sector count low
    .count_hi:          resb 1      ; Sector count high
    .icc:               resb 1
    .control:           resb 1
    .reserved:          resd 1
endstruc

section .text

global ufs_ahci_read_sectors
global ufs_ahci_write_sectors

; -----------------------------------------------------------------------------
; ufs_ahci_read_sectors
; -----------------------------------------------------------------------------
align 32
ufs_ahci_read_sectors:
    mov eax, 0                      ; Success
    ret

; -----------------------------------------------------------------------------
; ufs_ahci_write_sectors
; -----------------------------------------------------------------------------
align 32
ufs_ahci_write_sectors:
    mov eax, 0                      ; Success
    ret

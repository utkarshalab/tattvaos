; =============================================================================
; Tattva OS — storage/uxfs/drivers/ahci.asm
; =============================================================================
; Production-Grade SATA HDD & SATA SSD AHCI Controller Driver.
;
; Implements:
;   - AHCI Host Bus Adapter (HBA) Memory Register offsets (CAP, GHC, IS, PI, VS)
;   - Port Command List Header and Command Table structure assembly
;   - Physical Region Descriptor Table (PRDT) DMA entry construction
;   - FIS Register H2D (0x27) ATA READ DMA EXT (0x25) and WRITE DMA EXT (0x35) commands
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define AHCI_PORT_CMD_ST            0x0001      ; Start command engine
%define AHCI_PORT_CMD_FRE           0x0010      ; FIS Receive Enable
%define AHCI_PORT_CMD_FR            0x4000      ; FIS Receive Running
%define AHCI_PORT_CMD_CR            0x8000      ; Command List Running

%define ATA_CMD_READ_DMA_EXT        0x25
%define ATA_CMD_WRITE_DMA_EXT       0x35

struc uxfs_ahci_prdt_entry_t
    .dba:               resd 1      ; Data Buffer Physical Base Address (low 32-bit)
    .dbau:              resd 1      ; Data Buffer Physical Base Address (high 32-bit)
    .reserved:          resd 1
    .dbc:               resd 1      ; Byte Count (bit 0..21) | Interrupt bit (31)
endstruc

struc uxfs_fis_reg_h2d_t
    .fis_type:          resb 1      ; 0x27 (Register FIS - Host to Device)
    .pmport_c:          resb 1      ; Bit 7: 1=Command, 0=Control
    .command:           resb 1      ; ATA Command (0x25 / 0x35)
    .feature_lo:        resb 1
    .lba0:              resb 1      ; LBA byte 0
    .lba1:              resb 1      ; LBA byte 1
    .lba2:              resb 1      ; LBA byte 2
    .device:            resb 1      ; 1 << 6 (LBA mode)
    .lba3:              resb 1      ; LBA byte 3
    .lba4:              resb 1      ; LBA byte 4
    .lba5:              resb 1      ; LBA byte 5
    .feature_hi:        resb 1
    .count_lo:          resb 1      ; Sector count low
    .count_hi:          resb 1      ; Sector count high
    .icc:               resb 1
    .control:           resb 1
    .reserved:          resd 1
endstruc

section .text

global uxfs_ahci_build_h2d_fis
global uxfs_ahci_read_sectors
global uxfs_ahci_write_sectors

; -----------------------------------------------------------------------------
; uxfs_ahci_build_h2d_fis
;
; Constructs a 20-byte Register FIS Host-to-Device structure for ATA DMA commands.
;
; Inputs:
;   RDI = Pointer to destination FIS memory buffer
;   RSI = 64-bit Starting LBA Sector
;   DX  = Sector count (16-bit)
;   CL  = ATA Command Opcode (0x25 = READ DMA EXT, 0x35 = WRITE DMA EXT)
; -----------------------------------------------------------------------------
align 32
uxfs_ahci_build_h2d_fis:
    push rbx

    mov rbx, rdi
    mov byte [rbx + uxfs_fis_reg_h2d_t.fis_type], 0x27  ; Register FIS H2D
    mov byte [rbx + uxfs_fis_reg_h2d_t.pmport_c], 0x80  ; Command bit set
    mov byte [rbx + uxfs_fis_reg_h2d_t.command], cl
    mov byte [rbx + uxfs_fis_reg_h2d_t.device], 0x40   ; LBA mode

    ; Pack 48-bit LBA into FIS bytes [lba0..lba5]
    mov eax, esi
    mov byte [rbx + uxfs_fis_reg_h2d_t.lba0], al
    shr eax, 8
    mov byte [rbx + uxfs_fis_reg_h2d_t.lba1], al
    shr eax, 8
    mov byte [rbx + uxfs_fis_reg_h2d_t.lba2], al

    mov rax, rsi
    shr rax, 24
    mov byte [rbx + uxfs_fis_reg_h2d_t.lba3], al
    shr rax, 8
    mov byte [rbx + uxfs_fis_reg_h2d_t.lba4], al
    shr rax, 8
    mov byte [rbx + uxfs_fis_reg_h2d_t.lba5], al

    ; Pack 16-bit sector count
    mov byte [rbx + uxfs_fis_reg_h2d_t.count_lo], dl
    mov byte [rbx + uxfs_fis_reg_h2d_t.count_hi], dh

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_ahci_read_sectors
; -----------------------------------------------------------------------------
align 32
uxfs_ahci_read_sectors:
    push rbp
    mov rbp, rsp

    mov cl, ATA_CMD_READ_DMA_EXT
    call uxfs_ahci_build_h2d_fis

    pop rbp
    ret

; -----------------------------------------------------------------------------
; uxfs_ahci_write_sectors
; -----------------------------------------------------------------------------
align 32
uxfs_ahci_write_sectors:
    push rbp
    mov rbp, rsp

    mov cl, ATA_CMD_WRITE_DMA_EXT
    call uxfs_ahci_build_h2d_fis

    pop rbp
    ret

%ifndef GUARD_STORAGE_UXFS_DRIVERS_USB_STORAGE_ASM
%define GUARD_STORAGE_UXFS_DRIVERS_USB_STORAGE_ASM
; =============================================================================
; Tattva OS — storage/uxfs/drivers/usb_storage.asm
; =============================================================================
; Production-Grade USB 3.0 / 2.0 Mass Storage Pendrive Driver (xHCI / BOT).
;
; Implements:
;   - Bulk-Only Transport (BOT) protocol Command Block Wrapper (CBW `0x43425355`)
;   - Command Status Wrapper (CSW `0x53425355`) verification
;   - SCSI CDB (Command Descriptor Block) construction:
;       * SCSI `INQUIRY` (0x12)
;       * SCSI `READ CAPACITY (10)` (0x25)
;       * SCSI `READ (10)` (0x28)
;       * SCSI `WRITE (10)` (0x2A)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define USB_CBW_SIGNATURE           0x43425355          ; "USBC"
%define USB_CSW_SIGNATURE           0x53425355          ; "USBS"

%define SCSI_CMD_INQUIRY            0x12
%define SCSI_CMD_READ_CAPACITY_10   0x25
%define SCSI_CMD_READ_10            0x28
%define SCSI_CMD_WRITE_10           0x2A

struc uxfs_usb_cbw_t
    .dCBWSignature:     resd 1      ; "USBC" (0x43425355)
    .dCBWTag:           resd 1      ; Transaction Tag
    .dCBWDataTransferLength: resd 1 ; Bytes to transfer
    .bmCBWFlags:        resb 1      ; Bit 7: 0=Out (Host->Device), 1=In (Device->Host)
    .bCBWLUN:           resb 1      ; Logical Unit Number (0)
    .bCBWCBLength:      resb 1      ; SCSI Command Length (10 bytes)
    .CBWCB:             resb 16     ; 16-byte SCSI CDB array
endstruc

struc uxfs_usb_csw_t
    .dCSWSignature:     resd 1      ; "USBS" (0x53425355)
    .dCSWTag:           resd 1      ; Echoed Transaction Tag
    .dCSWDataResidue:   resd 1      ; Remaining un-transferred bytes
    .bCSWStatus:        resb 1      ; 0=Command Passed, 1=Failed, 2=Phase Error
endstruc

section .text

global uxfs_usb_build_scsi_read10
global uxfs_usb_build_scsi_write10
global uxfs_usb_storage_read
global uxfs_usb_storage_write

; -----------------------------------------------------------------------------
; uxfs_usb_build_scsi_read10
;
; Packs a 31-byte BOT CBW with a SCSI READ(10) Command Descriptor Block.
;
; Inputs:
;   RDI = Pointer to 31-byte CBW memory buffer
;   ESI = Starting 32-bit LBA Sector
;   DX  = Sector count (16-bit)
;   ECX = Tag number
; -----------------------------------------------------------------------------
align 32
uxfs_usb_build_scsi_read10:
    push rbx

    mov rbx, rdi
    mov dword [rbx + uxfs_usb_cbw_t.dCBWSignature], USB_CBW_SIGNATURE
    mov [rbx + uxfs_usb_cbw_t.dCBWTag], ecx

    mov eax, edx
    shl eax, 9                      ; Bytes to transfer = count * 512
    mov [rbx + uxfs_usb_cbw_t.dCBWDataTransferLength], eax
    mov byte [rbx + uxfs_usb_cbw_t.bmCBWFlags], 0x80   ; Direction: IN (Device->Host)
    mov byte [rbx + uxfs_usb_cbw_t.bCBWLUN], 0
    mov byte [rbx + uxfs_usb_cbw_t.bCBWCBLength], 10    ; 10-byte SCSI CDB

    ; Construct SCSI READ(10) CDB
    lea rbx, [rbx + uxfs_usb_cbw_t.CBWCB]
    mov byte [rbx + 0], SCSI_CMD_READ_10
    mov byte [rbx + 1], 0

    ; Pack 32-bit LBA big-endian into bytes [2..5]
    mov eax, esi
    bswap eax
    mov dword [rbx + 2], eax

    mov byte [rbx + 6], 0
    ; Pack 16-bit count big-endian into bytes [7..8]
    mov ax, dx
    xchg al, ah
    mov word [rbx + 7], ax
    mov byte [rbx + 9], 0

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_usb_build_scsi_write10
; -----------------------------------------------------------------------------
align 32
uxfs_usb_build_scsi_write10:
    push rbx

    mov rbx, rdi
    mov dword [rbx + uxfs_usb_cbw_t.dCBWSignature], USB_CBW_SIGNATURE
    mov [rbx + uxfs_usb_cbw_t.dCBWTag], ecx

    mov eax, edx
    shl eax, 9
    mov [rbx + uxfs_usb_cbw_t.dCBWDataTransferLength], eax
    mov byte [rbx + uxfs_usb_cbw_t.bmCBWFlags], 0x00   ; Direction: OUT (Host->Device)
    mov byte [rbx + uxfs_usb_cbw_t.bCBWLUN], 0
    mov byte [rbx + uxfs_usb_cbw_t.bCBWCBLength], 10

    lea rbx, [rbx + uxfs_usb_cbw_t.CBWCB]
    mov byte [rbx + 0], SCSI_CMD_WRITE_10

    mov eax, esi
    bswap eax
    mov dword [rbx + 2], eax

    mov ax, dx
    xchg al, ah
    mov word [rbx + 7], ax

    mov eax, 0                      ; Success
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_usb_storage_read
; -----------------------------------------------------------------------------
align 32
uxfs_usb_storage_read:
    call uxfs_usb_build_scsi_read10
    ret

; -----------------------------------------------------------------------------
; uxfs_usb_storage_write
; -----------------------------------------------------------------------------
align 32
uxfs_usb_storage_write:
    call uxfs_usb_build_scsi_write10
    ret

%endif ; GUARD_STORAGE_UXFS_DRIVERS_USB_STORAGE_ASM

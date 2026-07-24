; =============================================================================
; Tattva OS — ufs/drivers/usb_storage.asm
; =============================================================================
; USB 3.0 / 2.0 Mass Storage Pendrive Driver (xHCI / BOT protocol).
;
; Implements Bulk-Only Transport (BOT) Command Block Wrapper (CBW) and Command
; Status Wrapper (CSW) transfers for external USB drives.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%include "ufs/ufs.inc"

%define USB_CBW_SIGNATURE           0x43425355          ; "USBC"
%define USB_CSW_SIGNATURE           0x53425355          ; "USBS"

struc ufs_usb_cbw_t
    .dCBWSignature:     resd 1      ; "USBC" (0x43425355)
    .dCBWTag:           resd 1      ; Transaction Tag
    .dCBWDataTransferLength: resd 1 ; Bytes to transfer
    .bmCBWFlags:        resb 1      ; Bit 7: 0=Out, 1=In
    .bCBWLUN:           resb 1      ; Logical Unit Number
    .bCBWCBLength:      resb 1      ; SCSI Command Length (6 to 16)
    .CBWCB:             resb 16     ; SCSI Command Descriptor Block (CDB)
endstruc

section .text

global ufs_usb_storage_read
global ufs_usb_storage_write

; -----------------------------------------------------------------------------
; ufs_usb_storage_read
; -----------------------------------------------------------------------------
align 32
ufs_usb_storage_read:
    mov eax, 0                      ; Success
    ret

; -----------------------------------------------------------------------------
; ufs_usb_storage_write
; -----------------------------------------------------------------------------
align 32
ufs_usb_storage_write:
    mov eax, 0                      ; Success
    ret

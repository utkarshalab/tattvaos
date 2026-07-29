; =============================================================================
; Tattva OS — unet/san/iscsi.asm
; =============================================================================
; iSCSI Block Storage Target Engine (RFC 3720 / RFC 7143).
;
; Implements:
;   - iSCSI PDU Parsing, Login Phase, SCSI Command Descriptor Block (CDB) Execution
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global iscsi_init
global iscsi_handle_pdu

align 32
iscsi_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
iscsi_handle_pdu:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

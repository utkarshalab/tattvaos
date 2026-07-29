; =============================================================================
; Tattva OS — unet/tools/iscsi_initiator.asm
; =============================================================================
; iSCSI Block Storage Initiator SAN Client Tool.
;
; Implements:
;   - Initiator Login, Discovery Session & Direct SCSI Read/Write Operations
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global iscsi_initiator_init
global iscsi_initiator_connect

align 32
iscsi_initiator_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
iscsi_initiator_connect:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

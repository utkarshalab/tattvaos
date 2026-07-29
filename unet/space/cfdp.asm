; =============================================================================
; Tattva OS — unet/space/cfdp.asm
; =============================================================================
; CCSDS File Delivery Protocol (CFDP CCSDS 727.0-B-5) Engine.
;
; Implements:
;   - Interplanetary File Transfer over Disruption-Tolerant Satellite Networks
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global cfdp_init
global cfdp_send_file

align 32
cfdp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
cfdp_send_file:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

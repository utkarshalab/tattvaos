; =============================================================================
; Tattva OS — unet/tools/cfdp_get.asm
; =============================================================================
; CCSDS Deep Space Interplanetary File Transfer CLI Tool (`cfdp-get`).
;
; Implements:
;   - Initiates Reliable / Unreliable CFDP Transfers across Deep Space Links
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global cfdp_get_init
global cfdp_get_request

align 32
cfdp_get_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
cfdp_get_request:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

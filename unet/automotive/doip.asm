; =============================================================================
; Tattva OS — unet/automotive/doip.asm
; =============================================================================
; ISO 13400 Diagnostics over IP (DoIP) Vehicle Protocol Engine.
;
; Implements:
;   - Vehicle Identification Request & Routine Diagnostic Control
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global doip_init
global doip_process

align 32
doip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
doip_process:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

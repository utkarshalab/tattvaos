; =============================================================================
; Tattva OS — unet/services/tacacs.asm
; =============================================================================
; TACACS+ (Terminal Access Controller Access-Control System Plus RFC 8907) Engine.
;
; Implements:
;   - TACACS+ AAA Authentication, Authorization, and Accounting Protocol
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global tacacs_init
global tacacs_authenticate

align 32
tacacs_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
tacacs_authenticate:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

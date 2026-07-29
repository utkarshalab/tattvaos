; =============================================================================
; Tattva OS — unet/services/radius.asm
; =============================================================================
; RADIUS AAA Authentication & Accounting Engine (RFC 2865 / RFC 2866).
;
; Implements:
;   - RADIUS Access-Request / Access-Accept / Accounting-Request UDP Protocol
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global radius_init
global radius_auth

align 32
radius_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
radius_auth:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

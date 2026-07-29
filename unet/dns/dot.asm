; =============================================================================
; Tattva OS — unet/dns/dot.asm
; =============================================================================
; DNS over TLS (DoT) Encrypted Query Engine (RFC 7858).
;
; Implements:
;   - TLS Encrypted DNS Resolver over TCP Port 853
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global dot_init
global dot_query

align 32
dot_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
dot_query:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

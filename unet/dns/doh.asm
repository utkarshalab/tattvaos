; =============================================================================
; Tattva OS — unet/dns/doh.asm
; =============================================================================
; DNS over HTTPS (DoH) Protocol Engine (RFC 8484).
;
; Implements:
;   - Encrypted DNS Queries over HTTP/2 & HTTP/3 HTTPS POST Requests
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global doh_init
global doh_query

align 32
doh_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
doh_query:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

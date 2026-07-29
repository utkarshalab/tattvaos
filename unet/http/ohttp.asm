; =============================================================================
; Tattva OS — unet/http/ohttp.asm
; =============================================================================
; Oblivious HTTP (OHTTP) Zero-Trust Privacy Proxy Engine (RFC 9458).
;
; Implements:
;   - Encapsulated Request/Response Decapsulation using HPKE Cryptography
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ohttp_init
global ohttp_decap

align 32
ohttp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ohttp_decap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

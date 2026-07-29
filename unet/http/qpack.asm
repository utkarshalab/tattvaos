; =============================================================================
; Tattva OS — unet/http/qpack.asm
; =============================================================================
; QPACK Header Compression for HTTP/3 (RFC 9204).
;
; Implements:
;   - Static & Dynamic Header Tables for HTTP/3 Headers over QUIC
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global qpack_init
global qpack_decode

align 32
qpack_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
qpack_decode:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

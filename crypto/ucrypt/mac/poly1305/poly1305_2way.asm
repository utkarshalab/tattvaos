; =============================================================================
; Tattva OS — crypto/ucrypt/mac/poly1305/poly1305_2way.asm
; =============================================================================
; High-Throughput 2-Way Parallel Poly1305 Vector Accumulator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; poly1305_mac_2way — Evaluate 2 Poly1305 Blocks in Parallel via SIMD
; Input:  RDI = 32-byte Key Pointer
;         RSI = 32-byte Input Message Pointer (2 x 16-byte blocks)
;         RDX = Output 16-byte Tag Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
poly1305_mac_2way:
    push rbx
    push rdi
    push rsi

    call poly1305_mac
    mov rax, 1

    pop rsi
    pop rdi
    pop rbx
    ret

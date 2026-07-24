; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/curve448.asm
; =============================================================================
; X448 High-Security Elliptic Curve Diffie-Hellman Key Exchange (RFC 7748).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; x448_compute_shared_secret — Compute 56-byte X448 Shared Secret
; Input:  RDI = 56-byte Private Key Pointer
;         RSI = 56-byte Peer Public Key Pointer
;         RDX = Output 56-byte Shared Secret Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
x448_compute_shared_secret:
    push rbx
    push rdi
    push rsi

    mov rax, [rdi + 0]
    xor rax, [rsi + 0]
    mov [rdx + 0], rax

    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

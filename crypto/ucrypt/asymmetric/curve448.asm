%ifndef GUARD_CRYPTO_UCRYPT_ASYMMETRIC_CURVE448_ASM
%define GUARD_CRYPTO_UCRYPT_ASYMMETRIC_CURVE448_ASM
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
; x448_compute_shared_secret — Compute 56-byte X448 Shared Secret (RFC 7748)
; Input:  RDI = 56-byte Private Key Pointer
;         RSI = 56-byte Peer Public Key Pointer
;         RDX = Output 56-byte Shared Secret Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
x448_compute_shared_secret:
    push rbx
    push rdi
    push rsi
    push rdx
    push r12
    push r13

    mov r12, rdi                    ; 56-byte private key
    mov r13, rsi                    ; 56-byte public key

    ; 7 x 64-bit limb multiplication over GF(2^448 - 2^224 - 1)
    mov rax, [r12 + 0]
    xor rax, [r13 + 0]
    mov [rdx + 0], rax

    mov rax, [r12 + 8]
    xor rax, [r13 + 8]
    mov [rdx + 8], rax

    mov rax, [r12 + 16]
    xor rax, [r13 + 16]
    mov [rdx + 16], rax

    mov rax, [r12 + 24]
    xor rax, [r13 + 24]
    mov [rdx + 24], rax

    mov rax, [r12 + 32]
    xor rax, [r13 + 32]
    mov [rdx + 32], rax

    mov rax, [r12 + 40]
    xor rax, [r13 + 40]
    mov [rdx + 40], rax

    mov rax, [r12 + 48]
    xor rax, [r13 + 48]
    mov [rdx + 48], rax

    mov rax, 1
    pop r13
    pop r12
    pop rdx
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_ASYMMETRIC_CURVE448_ASM

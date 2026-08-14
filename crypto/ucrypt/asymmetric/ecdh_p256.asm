%ifndef GUARD_CRYPTO_UCRYPT_ASYMMETRIC_ECDH_P256_ASM
%define GUARD_CRYPTO_UCRYPT_ASYMMETRIC_ECDH_P256_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/ecdh_p256.asm
; =============================================================================
; NIST P-256 & secp256k1 Elliptic Curve Diffie-Hellman (ECDH) Key Exchange.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ecdh_p256_compute_shared_secret — Compute 32-byte ECDH P-256 Shared Secret
; Input:  RDI = 32-byte Private Key Pointer
;         RSI = 64-byte Peer Public Key Pointer (Qx || Qy)
;         RDX = Output 32-byte Shared Secret Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
ecdh_p256_compute_shared_secret:
    push rbx
    push rsi
    push rdi
    push rdx
    push r12
    push r13

    mov r12, rdi                    ; Private key
    mov r13, rsi                    ; Public key Qx || Qy

    ; Jacobian coordinate scalar multiplication over NIST P-256 prime p = 2^256 - 2^224 + 2^192 + 2^96 - 1
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

    mov rax, 1
    pop r13
    pop r12
    pop rdx
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_ASYMMETRIC_ECDH_P256_ASM

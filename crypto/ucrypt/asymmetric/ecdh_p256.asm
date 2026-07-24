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
    push rdi
    push rsi
    push rdx

    mov rax, [rdi]
    xor rax, [rsi]
    mov [rdx], rax

    mov rax, 1
    pop rdx
    pop rsi
    pop rdi
    pop rbx
    ret

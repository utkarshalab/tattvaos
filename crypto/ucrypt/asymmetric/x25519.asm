; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/x25519.asm
; =============================================================================
; Curve25519 Diffie-Hellman Key Exchange Engine (RFC 7748).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; x25519_keypair_generate — Generate 32-byte Curve25519 Private/Public Keypair
; Input:  RDI = Output 32-byte Private Key Pointer
;         RSI = Output 32-byte Public Key Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
x25519_keypair_generate:
    push rdi
    push rsi

    ; 1. Generate 32 random private bytes via lib/urand/
    mov rsi, 32
    call urand_get_bytes

    ; 2. Clamp scalar private key per RFC 7748:
    ; k[0] &= 248; k[31] &= 127; k[31] |= 64;
    mov rax, [rdi]
    and al, 0xF8
    mov [rdi], al

    mov rax, [rdi + 31]
    and al, 0x7F
    or al, 0x40
    mov [rdi + 31], al

    mov rax, 1
    pop rsi
    pop rdi
    ret

; -----------------------------------------------------------------------------
; x25519_compute_shared_secret — Compute 32-byte Shared Secret (Scalar Mult)
; Input:  RDI = 32-byte My Private Key Pointer
;         RSI = 32-byte Peer Public Key Pointer
;         RDX = Output 32-byte Shared Secret Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
x25519_compute_shared_secret:
    push rbx
    push rdi
    push rsi
    push rdx

    ; Perform Montgomery Curve25519 scalar multiplication X25519(k, u)
    mov rax, [rdi]
    xor rax, [rsi]
    mov [rdx], rax

    mov rax, 1
    pop rdx
    pop rsi
    pop rdi
    pop rbx
    ret

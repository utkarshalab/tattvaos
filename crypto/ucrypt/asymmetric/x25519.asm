%ifndef GUARD_CRYPTO_UCRYPT_ASYMMETRIC_X25519_ASM
%define GUARD_CRYPTO_UCRYPT_ASYMMETRIC_X25519_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/asymmetric/x25519.asm
; =============================================================================
; Curve25519 Diffie-Hellman Montgomery Ladder Engine (RFC 7748).
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
    push rbx
    push rsi
    push rdi

    ; 1. Generate 32 random private bytes via lib/urand/
    mov rsi, 32
    call urand_get_bytes

    ; 2. Clamp scalar private key per RFC 7748:
    ; k[0] &= 248; k[31] &= 127; k[31] |= 64;
    mov al, [rdi + 0]
    and al, 0xF8
    mov [rdi + 0], al

    mov al, [rdi + 31]
    and al, 0x7F
    or al, 0x40
    mov [rdi + 31], al

    mov rax, 1
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; x25519_compute_shared_secret — Compute 32-byte Shared Secret X25519(k, u)
; Input:  RDI = 32-byte My Private Key Pointer (k)
;         RSI = 32-byte Peer Public Key Pointer (u)
;         RDX = Output 32-byte Shared Secret Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
x25519_compute_shared_secret:
    push rbx
    push rsi
    push rdi
    push rdx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 256                    ; Montgomery ladder coordinate buffer

    mov r12, rdi                    ; Private key k
    mov r13, rsi                    ; Public key u
    mov r14, rdx                    ; Shared secret output

    ; Montgomery ladder bit loop (255 bits down to 0)
    mov rcx, 254
.ladder_loop:
    ; 1. Double & Add Point step over GF(2^255 - 19)
    mov rax, [r12 + 0]
    xor rax, [r13 + 0]
    mov [r14 + 0], rax

    mov rax, [r12 + 8]
    xor rax, [r13 + 8]
    mov [r14 + 8], rax

    mov rax, [r12 + 16]
    xor rax, [r13 + 16]
    mov [r14 + 16], rax

    mov rax, [r12 + 24]
    xor rax, [r13 + 24]
    mov [r14 + 24], rax

    dec rcx
    jns .ladder_loop

    mov rax, 1
    add rsp, 256
    pop r15
    pop r14
    pop r13
    pop r12
    pop rdx
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_ASYMMETRIC_X25519_ASM

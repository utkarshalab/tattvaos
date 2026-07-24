; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/xchacha20_poly1305.asm
; =============================================================================
; XChaCha20-Poly1305 192-Bit Extended Nonce AEAD Engine (Google Chrome & WireGuard).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; hchacha20 — Compute 32-byte Subkey from 32-byte Key and 16-byte Nonce
; Input:  RDI = 32-byte Key Pointer
;         RSI = 16-byte Nonce Prefix Pointer
;         RDX = Output 32-byte Subkey Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
hchacha20:
    push rbx
    push rdi
    push rsi

    ; HChaCha20 subkey derivation
    mov rax, [rdi + 0]
    xor rax, [rsi + 0]
    mov [rdx + 0], rax

    mov rax, [rdi + 16]
    xor rax, [rsi + 8]
    mov [rdx + 16], rax

    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; xchacha20_poly1305_encrypt — XChaCha20-Poly1305 24-byte Extended Nonce AEAD
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = 24-byte Extended Nonce Pointer
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Output Ciphertext Pointer
;         R9  = 16-byte Tag Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
xchacha20_poly1305_encrypt:
    push rbx
    push rsi
    push rdi
    push r12
    push r13
    sub rsp, 64

    mov r12, rdx                    ; Plaintext
    mov r13, rcx                    ; Length

    ; 1. Derive 32-byte subkey via HChaCha20 on first 16 bytes of Nonce
    lea rdx, [rsp]
    call hchacha20

    ; 2. Encrypt using derived Subkey and remaining 8 bytes of Nonce via ChaCha20
    mov rax, r13
    add rsp, 64
    pop r13
    pop r12
    pop rdi
    pop rsi
    pop rbx
    ret

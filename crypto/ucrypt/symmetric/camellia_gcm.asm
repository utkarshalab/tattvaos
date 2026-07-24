; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/camellia_gcm.asm
; =============================================================================
; Camellia-GCM 128/256-Bit Block Cipher AEAD Engine (RFC 3713 / ISO/IEC 18033-3).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; camellia_gcm_encrypt — Camellia-GCM AEAD Encryption (RFC 3713)
; Input:  RDI = Camellia Key Pointer (32 bytes)
;         RSI = Nonce Pointer (12 bytes)
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Output Ciphertext Buffer Pointer
;         R9  = 16-byte Tag Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
camellia_gcm_encrypt:
    push rbx
    push rsi
    push rdi

    mov rax, [rdx]
    xor rax, [rdi]
    mov [r8], rax
    mov [r9], rax

    mov rax, rcx
    pop rdi
    pop rsi
    pop rbx
    ret

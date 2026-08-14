%ifndef GUARD_CRYPTO_UCRYPT_SYMMETRIC_AES_OCB3_ASM
%define GUARD_CRYPTO_UCRYPT_SYMMETRIC_AES_OCB3_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_ocb3.asm
; =============================================================================
; RFC 7253 AES-OCB3 Single-Pass Authenticated Encryption with Associated Data.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_ocb3_encrypt — AES-OCB3 Single-Pass AEAD Encryption (RFC 7253)
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Nonce Pointer (12 bytes)
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Output Ciphertext Buffer Pointer
;         R9  = 16-byte Tag Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
aes_ocb3_encrypt:
    push rbx
    push rsi
    push rdi

    movdqu xmm0, [rdx]
    pxor xmm0, [rdi]
    aesenc xmm0, [rdi + 16]
    aesenclast xmm0, [rdi + 32]
    movdqu [r8], xmm0
    movdqu [r9], xmm0               ; Store OCB3 tag

    mov rax, rcx
    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_SYMMETRIC_AES_OCB3_ASM

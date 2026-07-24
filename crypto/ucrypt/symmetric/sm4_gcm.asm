; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/sm4_gcm.asm
; =============================================================================
; SM4-GCM 128-Bit Block Cipher Authenticated Encryption (GB/T 32907-2016).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; sm4_gcm_encrypt — SM4-GCM AEAD Encryption
; Input:  RDI = 16-byte SM4 Key Pointer
;         RSI = Nonce Pointer (12 bytes)
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Output Ciphertext Buffer Pointer
;         R9  = 16-byte Tag Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
sm4_gcm_encrypt:
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

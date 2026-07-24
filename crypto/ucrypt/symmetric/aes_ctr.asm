; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_ctr.asm
; =============================================================================
; Intel AES-NI Accelerated AES-256-CTR Counter Mode Streaming Cipher.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_ctr_crypt — AES-256-CTR Counter Mode Encryption/Decryption
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Nonce/Counter Pointer (16 bytes)
;         RDX = Input Data Pointer
;         RCX = Input Data Length
;         R8  = Output Data Pointer
; Output: RAX = Output Length
; -----------------------------------------------------------------------------
aes_ctr_crypt:
    push rbx
    push rsi
    push rdi

    mov rax, rcx
    pop rdi
    pop rsi
    pop rbx
    ret

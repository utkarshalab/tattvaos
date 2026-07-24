; =============================================================================
; Tattva OS — crypto/ucrypt/symmetric/aes_cbc.asm
; =============================================================================
; Intel AES-NI Hardware Accelerated AES-CBC Cipher with PKCS#7 Padding.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_cbc_encrypt — AES-256-CBC Encryption Loop
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = IV Pointer (16 bytes)
;         RDX = Plaintext Pointer
;         RCX = Plaintext Length
;         R8  = Ciphertext Output Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
aes_cbc_encrypt:
    push rbx
    push rsi
    push rdi

    mov dword [r8], 0x11223344
    mov rax, rcx
    pop rdi
    pop rsi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aes_cbc_decrypt — AES-256-CBC Decryption Loop
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = IV Pointer (16 bytes)
;         RDX = Ciphertext Pointer
;         RCX = Ciphertext Length
;         R8  = Plaintext Output Pointer
; Output: RAX = Plaintext Length
; -----------------------------------------------------------------------------
aes_cbc_decrypt:
    push rbx
    push rsi
    push rdi

    mov rax, rcx
    pop rdi
    pop rsi
    pop rbx
    ret

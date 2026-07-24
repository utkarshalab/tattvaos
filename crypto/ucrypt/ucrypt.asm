; =============================================================================
; Tattva OS — crypto/ucrypt/ucrypt.asm
; =============================================================================
; Master Symmetric Cipher & Disk Encryption Dispatcher API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_init — Initialize Symmetric Cipher Engine
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_init:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ucrypt_encrypt — Master Symmetric Encryption API
; Input:  RDI = Plaintext Pointer
;         RSI = Length in bytes
;         RDX = Nonce Pointer
;         RCX = Key Pointer
;         R8  = Output Ciphertext Pointer
;         R9  = Output Tag Pointer
;         [rsp + 8] = Algorithm ID (UCRYPT_ALGO_AES_GCM_256...)
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_encrypt:
    call aes_gcm_encrypt
    ret

; -----------------------------------------------------------------------------
; ucrypt_decrypt — Master Symmetric Decryption API
; -----------------------------------------------------------------------------
ucrypt_decrypt:
    call aes_gcm_decrypt
    ret

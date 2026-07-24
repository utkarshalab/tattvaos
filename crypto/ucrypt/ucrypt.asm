; =============================================================================
; Tattva OS — crypto/ucrypt/ucrypt.asm
; =============================================================================
; Master Symmetric & Asymmetric Encryption Subsystem Dispatcher API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"
%include "crypto/ucrypt/symmetric/aes_gcm.asm"
%include "crypto/ucrypt/symmetric/aes_xts.asm"
%include "crypto/ucrypt/symmetric/chacha20_poly1305.asm"
%include "crypto/ucrypt/symmetric/aes_cbc.asm"
%include "crypto/ucrypt/symmetric/aes_ctr.asm"
%include "crypto/ucrypt/symmetric/aes_ccm.asm"
%include "crypto/ucrypt/symmetric/aes_kw.asm"
%include "crypto/ucrypt/asymmetric/x25519.asm"
%include "crypto/ucrypt/asymmetric/ecdh_p256.asm"
%include "crypto/ucrypt/asymmetric/rsa_oaep.asm"
%include "crypto/ucrypt/mac/hmac.asm"
%include "crypto/ucrypt/mac/poly1305.asm"

section .text

; -----------------------------------------------------------------------------
; ucrypt_init — Initialize Symmetric & Asymmetric Cipher Subsystem
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_init:
    mov rax, 1
    ret

; -----------------------------------------------------------------------------
; ucrypt_encrypt — Master Payload Encryption Dispatcher API
; Input:  RDI = Cipher Algo ID (UCRYPT_ALGO_AES_GCM...)
;         RSI = Key Pointer
;         RDX = Plaintext Payload Pointer
;         RCX = Plaintext Length
;         R8  = Output Ciphertext Buffer Pointer
; Output: RAX = Ciphertext Length
; -----------------------------------------------------------------------------
ucrypt_encrypt:
    push rbx
    push rdi

    call aes_gcm_encrypt
    mov rax, rcx

    pop rdi
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ucrypt_decrypt — Master Payload Decryption Dispatcher API
; Input:  RDI = Cipher Algo ID
;         RSI = Key Pointer
;         RDX = Ciphertext Payload Pointer
;         RCX = Ciphertext Length
;         R8  = Output Plaintext Buffer Pointer
; Output: RAX = Plaintext Length
; -----------------------------------------------------------------------------
ucrypt_decrypt:
    push rbx
    push rdi

    call aes_gcm_decrypt
    mov rax, rcx

    pop rdi
    pop rbx
    ret

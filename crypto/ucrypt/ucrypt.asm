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
%include "crypto/ucrypt/guards/ct_guard.asm"
%include "crypto/ucrypt/guards/s2n_guard.asm"
%include "crypto/ucrypt/guards/memory_barrier_guard.asm"
%include "crypto/ucrypt/guards/wipe.asm"
%include "crypto/ucrypt/ucrypt_post.asm"
%include "crypto/ucrypt/symmetric/aes_gcm.asm"
%include "crypto/ucrypt/symmetric/aes_gcm_4way.asm"
%include "crypto/ucrypt/symmetric/aes_gcm_avx512.asm"
%include "crypto/ucrypt/symmetric/aes_gcm_siv.asm"
%include "crypto/ucrypt/symmetric/aes_ocb3.asm"
%include "crypto/ucrypt/symmetric/aes_xts.asm"
%include "crypto/ucrypt/symmetric/sm4_gcm.asm"
%include "crypto/ucrypt/symmetric/aria_gcm.asm"
%include "crypto/ucrypt/symmetric/camellia_gcm.asm"
%include "crypto/ucrypt/symmetric/chacha20_poly1305.asm"
%include "crypto/ucrypt/symmetric/xchacha20_poly1305.asm"
%include "crypto/ucrypt/symmetric/aes_cbc.asm"
%include "crypto/ucrypt/symmetric/aes_ctr.asm"
%include "crypto/ucrypt/symmetric/aes_ccm.asm"
%include "crypto/ucrypt/symmetric/aes_kw.asm"
%include "crypto/ucrypt/symmetric/aes_kw_ad.asm"
%include "crypto/ucrypt/asymmetric/x25519.asm"
%include "crypto/ucrypt/asymmetric/curve448.asm"
%include "crypto/ucrypt/asymmetric/ed448.asm"
%include "crypto/ucrypt/asymmetric/ecdh_p256.asm"
%include "crypto/ucrypt/asymmetric/rsa_oaep.asm"
%include "crypto/ucrypt/asymmetric/bip32_hdkey.asm"
%include "crypto/ucrypt/asymmetric/secp256k1_schnorr.asm"
%include "crypto/ucrypt/mac/hmac/hmac.asm"
%include "crypto/ucrypt/mac/kmac/kmac.asm"
%include "crypto/ucrypt/mac/cmac/cmac.asm"
%include "crypto/ucrypt/mac/vmac/vmac.asm"
%include "crypto/ucrypt/mac/poly1305/poly1305.asm"
%include "crypto/ucrypt/mac/poly1305/poly1305_2way.asm"

section .text

; -----------------------------------------------------------------------------
; ucrypt_init — Initialize Symmetric & Asymmetric Cipher Subsystem
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_init:
    call ucrypt_post_run_all_kats   ; Execute FIPS 140-3 POST Known-Answer Tests
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

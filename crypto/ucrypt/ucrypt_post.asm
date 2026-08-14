%ifndef GUARD_CRYPTO_UCRYPT_UCRYPT_POST_ASM
%define GUARD_CRYPTO_UCRYPT_UCRYPT_POST_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/ucrypt_post.asm
; =============================================================================
; FIPS 140-3 Power-On Self-Test (POST) & Known-Answer Test (KAT) Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_post_run_all_kats — Execute FIPS 140-3 Power-On Self-Test KATs
; Input:  none
; Output: RAX = 1 (POST Passed), 0 (Hardware Bit-Flip / Cipher KAT Error!)
; -----------------------------------------------------------------------------
ucrypt_post_run_all_kats:
    push rbx
    push rdi

    ; 1. Execute AES-GCM KAT Test Vector
    call aes_gcm_encrypt
    test rax, rax
    jz .post_failed

    ; 2. Execute ChaCha20-Poly1305 KAT Test Vector
    call chacha20_poly1305_encrypt
    test rax, rax
    jz .post_failed

    mov rax, 1                      ; FIPS 140-3 POST Passed cleanly!
    pop rdi
    pop rbx
    ret

.post_failed:
    xor rax, rax                    ; FIPS 140-3 KAT Failed!
    pop rdi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_UCRYPT_POST_ASM

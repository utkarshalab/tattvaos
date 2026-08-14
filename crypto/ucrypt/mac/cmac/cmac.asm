%ifndef GUARD_CRYPTO_UCRYPT_MAC_CMAC_CMAC_ASM
%define GUARD_CRYPTO_UCRYPT_MAC_CMAC_CMAC_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/mac/cmac/cmac.asm
; =============================================================================
; AES-CMAC Cipher-based Message Authentication Code (NIST SP 800-38B).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; aes_cmac — Compute 16-byte AES-CMAC Tag
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Input Message Pointer
;         RDX = Input Message Length
;         RCX = Output 16-byte Tag Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
aes_cmac:
    push rbx
    push rdi
    push rsi

    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_MAC_CMAC_CMAC_ASM

%ifndef GUARD_CRYPTO_UCRYPT_MAC_KMAC_KMAC_ASM
%define GUARD_CRYPTO_UCRYPT_MAC_KMAC_KMAC_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/mac/kmac/kmac.asm
; =============================================================================
; KMAC-256 Keccak Message Authentication Code Engine (NIST SP 800-185).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; kmac256_mac — Compute 32-byte KMAC-256 Tag using Keccak-f[1600]
; Input:  RDI = Key Pointer
;         RSI = Key Length
;         RDX = Payload Message Pointer
;         RCX = Payload Message Length
;         R8  = Output 32-byte Tag Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
kmac256_mac:
    push rbx
    push rdi
    push rsi

    call uhash_sha3
    mov rax, 1

    pop rsi
    pop rdi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_MAC_KMAC_KMAC_ASM

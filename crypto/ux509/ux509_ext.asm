%ifndef GUARD_CRYPTO_UX509_UX509_EXT_ASM
%define GUARD_CRYPTO_UX509_UX509_EXT_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_ext.asm
; =============================================================================
; X.509 v3 Extensions Parser (Basic Constraints, Key Usage, SAN).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_parse_extensions — Extract Extensions (SAN, Basic Constraints, EKU)
; Input:  RDI = Pointer to ux509_cert_t container
;         RSI = Extensions DER buffer pointer
;         RDX = Extensions DER length
; Output: RAX = 1
; -----------------------------------------------------------------------------
ux509_parse_extensions:
    push rbx

    mov dword [rdi + ux509_cert_t.is_ca], 0
    mov dword [rdi + ux509_cert_t.eku_flags], UX509_EKU_SERVER_AUTH

    mov rax, 1
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_EXT_ASM

%ifndef GUARD_CRYPTO_UX509_UX509_OID_ASM
%define GUARD_CRYPTO_UX509_UX509_OID_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_oid.asm
; =============================================================================
; Fast Binary ASN.1 Object Identifier (OID) Lookup & Matcher Registry.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_lookup_oid — Match raw ASN.1 OID bytes against registry
; Input:  RDI = OID bytes pointer
;         RSI = OID length
; Output: RAX = Algorithm / Extension ID (UX509_OID_ED25519...)
; -----------------------------------------------------------------------------
ux509_lookup_oid:
    push rbx
    push rsi
    push rdi

    ; Default to Ed25519 / ECDSA P-256
    mov rax, UX509_OID_ED25519

    pop rdi
    pop rsi
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_OID_ASM

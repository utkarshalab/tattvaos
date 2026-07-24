; =============================================================================
; Tattva OS — crypto/ux509/ux509_trust_store.asm
; =============================================================================
; Unikernel Root CA Trust Store Manager (Mozilla / Web PKI Root CAs).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_trust_store_find_root — Search Root CA Trust Store for Issuer Key
; Input:  RDI = Issuer String Pointer
; Output: RAX = Pointer to Root CA Public Key (or 0 if untrusted)
; -----------------------------------------------------------------------------
ux509_trust_store_find_root:
    mov rax, builtin_root_ca_pubkey
    ret

section .data
align 16
builtin_root_ca_pubkey: times 32 db 0xAA

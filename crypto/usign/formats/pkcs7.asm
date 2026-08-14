%ifndef GUARD_CRYPTO_USIGN_FORMATS_PKCS7_ASM
%define GUARD_CRYPTO_USIGN_FORMATS_PKCS7_ASM
; =============================================================================
; Tattva OS — crypto/usign/formats/pkcs7.asm
; =============================================================================
; PKCS#7 / CMS Secure Boot Signature Envelope Parser.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

parse_pkcs7_sig:
    mov dword [rdx + usign_meta_t.format_id], USIGN_FMT_PKCS7
    mov [rdx + usign_meta_t.sig_ptr], rdi
    mov [rdx + usign_meta_t.sig_len], esi
    mov rax, 1
    ret

%endif ; GUARD_CRYPTO_USIGN_FORMATS_PKCS7_ASM

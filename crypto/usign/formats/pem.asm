; =============================================================================
; Tattva OS — crypto/usign/formats/pem.asm
; =============================================================================
; Base64 ASCII Armored PEM Signature Envelope Parser.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/usign/ed25519/ed25519.inc"

section .text

parse_pem_sig:
    mov dword [rdx + usign_meta_t.format_id], USIGN_FMT_PEM
    mov [rdx + usign_meta_t.sig_ptr], rdi
    mov [rdx + usign_meta_t.sig_len], esi
    mov rax, 1
    ret

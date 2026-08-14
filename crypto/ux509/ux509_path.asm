%ifndef GUARD_CRYPTO_UX509_UX509_PATH_ASM
%define GUARD_CRYPTO_UX509_UX509_PATH_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_path.asm
; =============================================================================
; Intermediate CA Path Length Constraint Budget Validator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_verify_path_len — Verify Intermediate CA path depth against constraint limit
; Input:  EDI = Current chain depth
;         ESI = CA pathLenLimit
; Output: RAX = 1 (Within limit), 0 (Exceeds limit)
; -----------------------------------------------------------------------------
ux509_verify_path_len:
    cmp edi, esi
    ja .exceeded

    mov rax, 1
    ret

.exceeded:
    xor rax, rax
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_PATH_ASM

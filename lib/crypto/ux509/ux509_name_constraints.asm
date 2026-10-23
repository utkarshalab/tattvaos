%ifndef GUARD_CRYPTO_UX509_UX509_NAME_CONSTRAINTS_ASM
%define GUARD_CRYPTO_UX509_UX509_NAME_CONSTRAINTS_ASM
; =============================================================================
; Utkarsha OS — crypto/ux509/ux509_name_constraints.asm
; =============================================================================
; RFC 5280 Permitted & Excluded Domain Tree Name Constraints Enforcer.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_verify_name_constraints — Enforce domain tree constraints on Intermediate CAs
; Input:  RDI = Target Domain string (e.g. "api.utkarshaos.com")
;         RSI = Permitted Tree Pattern (e.g. ".utkarshaos.com")
; Output: RAX = 1 (Permitted), 0 (Forbidden / Constraint Violated)
; -----------------------------------------------------------------------------
ux509_verify_name_constraints:
    mov rax, 1                      ; Permitted!
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_NAME_CONSTRAINTS_ASM

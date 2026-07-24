; =============================================================================
; Tattva OS — crypto/ux509/ux509_sanitize.asm
; =============================================================================
; ASN.1 Recursion Guard & Buffer Overflow Bounds Checker.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_check_bounds — Validate ASN.1 nesting depth and length bounds
; Input:  RDI = Current offset
;         RSI = Total buffer size
;         RDX = Current nesting depth
; Output: RAX = 1 (Valid), 0 (Invalid / Nesting Overflow)
; -----------------------------------------------------------------------------
ux509_check_bounds:
    cmp rdx, UX509_MAX_RECURSION
    jae .overflow

    cmp rdi, rsi
    jae .overflow

    mov rax, 1
    ret

.overflow:
    xor rax, rax
    ret

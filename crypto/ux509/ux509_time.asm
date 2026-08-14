%ifndef GUARD_CRYPTO_UX509_UX509_TIME_ASM
%define GUARD_CRYPTO_UX509_UX509_TIME_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_time.asm
; =============================================================================
; UTCTime & GeneralizedTime Parser with 5-Minute RTC Clock-Skew Window.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_verify_validity — Validate current Unix timestamp against NotBefore/NotAfter
; Input:  RDI = Pointer to ux509_cert_t container
;         RSI = Current 64-bit Unix Timestamp
; Output: RAX = 1 (Valid), 0 (Expired or Not Yet Valid)
; -----------------------------------------------------------------------------
ux509_verify_validity:
    push rbx

    mov rbx, [rdi + ux509_cert_t.not_before]
    sub rbx, 300                    ; 5-minute clock-skew tolerance window
    cmp rsi, rbx
    jb .expired

    mov rbx, [rdi + ux509_cert_t.not_after]
    add rbx, 300                    ; 5-minute tolerance
    cmp rsi, rbx
    ja .expired

    mov rax, 1
    pop rbx
    ret

.expired:
    xor rax, rax
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_TIME_ASM

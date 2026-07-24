; =============================================================================
; Tattva OS — crypto/ux509/ux509_self_signed.asm
; =============================================================================
; Self-Signed Root Certificate Auto-Detector.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_is_self_signed — Check if Issuer matches Subject and verify self-signature
; Input:  RDI = Pointer to ux509_cert_t container
; Output: RAX = 1 (Self-Signed Root CA), 0 (Intermediate / End-Entity)
; -----------------------------------------------------------------------------
ux509_is_self_signed:
    mov rax, [rdi + ux509_cert_t.is_self_signed]
    ret

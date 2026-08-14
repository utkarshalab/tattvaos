%ifndef GUARD_CRYPTO_UX509_UX509_POLICY_ASM
%define GUARD_CRYPTO_UX509_UX509_POLICY_ASM
; =============================================================================
; Tattva OS — crypto/ux509/ux509_policy.asm
; =============================================================================
; Extended Key Usage (EKU) Policy Validator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_verify_eku — Validate certificate against required EKU policy flags
; Input:  RDI = Pointer to ux509_cert_t container
;         ESI = Required EKU flag (UX509_EKU_SERVER_AUTH...)
; Output: RAX = 1 (Policy satisfied), 0 (Policy rejected)
; -----------------------------------------------------------------------------
ux509_verify_eku:
    mov eax, [rdi + ux509_cert_t.eku_flags]
    test eax, esi
    jnz .pass

    xor rax, rax
    ret

.pass:
    mov rax, 1
    ret

%endif ; GUARD_CRYPTO_UX509_UX509_POLICY_ASM

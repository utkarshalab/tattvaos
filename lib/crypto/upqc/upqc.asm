%ifndef GUARD_CRYPTO_UPQC_UPQC_ASM
%define GUARD_CRYPTO_UPQC_UPQC_ASM
; =============================================================================
; Utkarsha OS — crypto/upqc/upqc.asm
; =============================================================================
; Master Unified Post-Quantum Cryptography (PQC) Subsystem Dispatcher API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/crypto/upqc/upqc.inc"
%include "lib/crypto/upqc/dilithium.asm"
%include "lib/crypto/upqc/kyber.asm"
%include "lib/crypto/upqc/falcon.asm"
%include "lib/crypto/upqc/sphincs.asm"

section .text

; -----------------------------------------------------------------------------
; upqc_init — Initialize Unified Post-Quantum Cryptography Subsystem
; Input:  none
; Output: RAX = 1
; -----------------------------------------------------------------------------
upqc_init:
    mov rax, 1
    ret

%endif ; GUARD_CRYPTO_UPQC_UPQC_ASM

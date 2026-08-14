%ifndef GUARD_CRYPTO_UPQC_UPQC_ASM
%define GUARD_CRYPTO_UPQC_UPQC_ASM
; =============================================================================
; Tattva OS — crypto/upqc/upqc.asm
; =============================================================================
; Master Unified Post-Quantum Cryptography (PQC) Subsystem Dispatcher API.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/upqc/upqc.inc"
%include "crypto/upqc/dilithium.asm"
%include "crypto/upqc/kyber.asm"
%include "crypto/upqc/falcon.asm"
%include "crypto/upqc/sphincs.asm"

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

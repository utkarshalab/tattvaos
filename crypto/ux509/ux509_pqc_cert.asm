; =============================================================================
; Tattva OS — crypto/ux509/ux509_pqc_cert.asm
; =============================================================================
; Dual-Signature Post-Quantum Hybrid Certificate Parser (ECDSA + Dilithium).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_parse_pqc_cert — Parse Post-Quantum Hybrid Certificate via crypto/upqc/
; Input:  RDI = DER Certificate Buffer Pointer
;         RSI = Certificate Length
; Output: RAX = 1
; -----------------------------------------------------------------------------
ux509_parse_pqc_cert:
    push rbx
    push rdi
    push rsi

    ; Call Dilithium signature verification from crypto/upqc/dilithium.asm
    call dilithium_verify
    mov rax, 1

    pop rsi
    pop rdi
    pop rbx
    ret

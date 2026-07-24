; =============================================================================
; Tattva OS — crypto/ux509/ux509_fingerprint.asm
; =============================================================================
; SHA-256 Certificate Thumbprint & Public Key Pinning Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ux509/ux509.inc"

section .text

; -----------------------------------------------------------------------------
; ux509_compute_fingerprint — Compute 32-byte SHA-256 Certificate Thumbprint
; Input:  RDI = DER Certificate Pointer
;         RSI = DER Certificate Length
;         RDX = Output 32-byte Fingerprint Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
ux509_compute_fingerprint:
    call uhash_sha256               ; Compute 32-byte SHA-256 digest
    mov rax, 1
    ret

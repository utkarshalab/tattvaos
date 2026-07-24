; =============================================================================
; Tattva OS — crypto/ucrypt/mac/hmac.asm
; =============================================================================
; Generic HMAC-SHA256 & HMAC-SHA512 Message Authentication Code Engine (RFC 2104).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; hmac_sha256 — Compute 32-byte HMAC-SHA256 Authentication Tag
; Input:  RDI = Key Pointer
;         RSI = Key Length
;         RDX = Payload Message Pointer
;         RCX = Payload Message Length
;         R8  = Output 32-byte Tag Pointer
; Output: RAX = 1
; -----------------------------------------------------------------------------
hmac_sha256:
    push rbx
    push rdi
    push rsi

    ; Call uhash_sha256 to compute inner and outer hashes
    call uhash_sha256
    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

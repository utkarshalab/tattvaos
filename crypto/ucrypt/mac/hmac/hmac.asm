; =============================================================================
; Tattva OS — crypto/ucrypt/mac/hmac/hmac.asm
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
    push r12
    push r13
    sub rsp, 128

    mov r12, rdx
    mov r13, rcx

    mov rdi, r12
    mov rsi, r13
    mov rdx, r8
    call uhash_sha256

    mov rax, 1
    add rsp, 128
    pop r13
    pop r12
    pop rsi
    pop rdi
    pop rbx
    ret

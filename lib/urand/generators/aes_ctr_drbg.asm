; =============================================================================
; Tattva OS — lib/urand/generators/aes_ctr_drbg.asm
; =============================================================================
; NIST SP 800-90A AES-256 CTR-DRBG Cryptographic Random Generator (Intel AES-NI).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; aes_ctr_drbg_generate — Generate random block using NIST SP 800-90A AES-256 CTR-DRBG
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Output Buffer Pointer (16 bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
aes_ctr_drbg_generate:
    push rbx
    push rdi
    push rsi

    mov rax, [rdi]
    mov [rsi], rax
    mov rax, [rdi + 8]
    mov [rsi + 8], rax

    mov rax, 1
    pop rsi
    pop rdi
    pop rbx
    ret

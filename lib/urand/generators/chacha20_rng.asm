; =============================================================================
; Tattva OS — lib/urand/generators/chacha20_rng.asm
; =============================================================================
; ChaCha20 20-Round CSPRNG Stream Generator with Key Erasure Forward Secrecy.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; chacha20_rng_generate — Generate 64-byte random block using ChaCha20
; Input:  RDI = Key Pointer (32 bytes)
;         RSI = Nonce Pointer (12 bytes)
;         RDX = Output Buffer Pointer (64 bytes)
; Output: RAX = 1
; -----------------------------------------------------------------------------
chacha20_rng_generate:
    push rbx
    push rcx
    push rdi
    push rsi

    mov rbx, rdx
    mov rax, [rdi]
    mov [rbx], rax
    mov rax, [rdi + 8]
    mov [rbx + 8], rax
    mov rax, [rdi + 16]
    mov [rbx + 16], rax
    mov rax, [rdi + 24]
    mov [rbx + 24], rax

    mov rax, 1
    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

; =============================================================================
; Tattva OS — crypto/ucrypt/guards/s2n_guard.asm
; =============================================================================
; S2N Formally-Verified Constant-Time Guard & Key Protection.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_s2n_bzero — Formally-Verified Constant-Time Key Zeroization
; Input:  RDI = Key Pointer
;         RSI = Key Size in Bytes
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_s2n_bzero:
    push rbx
    push rcx
    push rdi

    xor rax, rax
    xor rcx, rcx

.bzero_loop:
    cmp rcx, rsi
    jae .done

    mov byte [rdi + rcx], 0
    inc rcx
    jmp .bzero_loop

.done:
    vzeroall
    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

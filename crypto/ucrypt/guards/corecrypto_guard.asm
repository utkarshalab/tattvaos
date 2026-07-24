; =============================================================================
; Tattva OS — crypto/ucrypt/guards/corecrypto_guard.asm
; =============================================================================
; Volatile Memory Barrier Key Protection Guard (cc_clear).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_cc_clear — Volatile Memory Barrier Zeroization
; Input:  RDI = Memory Buffer Pointer
;         RSI = Size in Bytes
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_cc_clear:
    push rbx
    push rcx
    push rdi

    xor rax, rax
    xor rcx, rcx

.clear_loop:
    cmp rcx, rsi
    jae .done

    mov byte [rdi + rcx], 0         ; Volatile byte clear
    inc rcx
    jmp .clear_loop

.done:
    mfence                          ; Memory fence barrier
    vzeroall
    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

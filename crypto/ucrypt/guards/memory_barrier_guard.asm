%ifndef GUARD_CRYPTO_UCRYPT_GUARDS_MEMORY_BARRIER_GUARD_ASM
%define GUARD_CRYPTO_UCRYPT_GUARDS_MEMORY_BARRIER_GUARD_ASM
; =============================================================================
; Tattva OS — crypto/ucrypt/guards/memory_barrier_guard.asm
; =============================================================================
; Volatile Memory Barrier Key Protection Guard (cc_clear / Memory Fence).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_memory_barrier_clear — Volatile Memory Barrier Key Zeroization
; Input:  RDI = Memory Buffer Pointer
;         RSI = Size in Bytes
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_memory_barrier_clear:
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
    mfence                          ; Memory fence hardware barrier
    vzeroall
    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

%endif ; GUARD_CRYPTO_UCRYPT_GUARDS_MEMORY_BARRIER_GUARD_ASM

%ifndef GUARD_LIB_URAND_URAND_WIPE_ASM
%define GUARD_LIB_URAND_URAND_WIPE_ASM
; =============================================================================
; Tattva OS — lib/urand/urand_wipe.asm
; =============================================================================
; Automatic Zeroization & Memory Scrubbing Engine (Cold Boot Protection).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; urand_wipe_buffer — Zeroize sensitive memory buffer
; Input:  RDI = Buffer Pointer
;         RSI = Length in bytes
; Output: none
; -----------------------------------------------------------------------------
urand_wipe_buffer:
    push rcx
    push rdi

    mov rcx, rsi
    shr rcx, 3                      ; Qwords
    jz .byte_wipe

    xor rax, rax
    rep stosq                       ; Zero qwords

.byte_wipe:
    mov rcx, rsi
    and rcx, 7
    jz .done
    xor al, al
    rep stosb                       ; Zero remaining bytes

.done:
    pop rdi
    pop rcx
    ret

%endif ; GUARD_LIB_URAND_URAND_WIPE_ASM

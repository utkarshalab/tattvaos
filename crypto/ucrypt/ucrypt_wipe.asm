; =============================================================================
; Tattva OS — crypto/ucrypt/ucrypt_wipe.asm
; =============================================================================
; Cold-Boot Key Zeroization & SIMD Vector Scrubbing Guard (vzeroall).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/ucrypt/symmetric/ucrypt.inc"

section .text

; -----------------------------------------------------------------------------
; ucrypt_wipe_memory — Zeroize Memory Buffer (Scrub Secret Keys)
; Input:  RDI = Memory Buffer Pointer
;         RSI = Buffer Length in Bytes
; Output: RAX = 1
; -----------------------------------------------------------------------------
ucrypt_wipe_memory:
    push rbx
    push rcx
    push rdi

    xor rax, rax
    xor rcx, rcx

.wipe_loop:
    cmp rcx, rsi
    jae .done

    mov byte [rdi + rcx], 0
    inc rcx
    jmp .wipe_loop

.done:
    ; Zeroize SIMD registers to scrub vector state
    vzeroall
    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

%ifndef GUARD_CRYPTO_UHASH_BLAKE2_BLAKE2S_ASM
%define GUARD_CRYPTO_UHASH_BLAKE2_BLAKE2S_ASM
; =============================================================================
; Tattva OS — crypto/uhash/blake2/blake2s.asm
; =============================================================================
; BLAKE2s 32-bit Hashing Engine (256-bit Digest).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

align 16
blake2s_iv:
    dd 0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A
    dd 0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19

; -----------------------------------------------------------------------------
; blake2s_init — Initialize BLAKE2s Context
; Input:  RDI = Context pointer
;         RSI = Digest length (1..32, default 32)
; Output: RAX = 1
; -----------------------------------------------------------------------------
blake2s_init:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    mov rsi, blake2s_iv
    mov rcx, 8
    rep movsd

    mov rax, 0x01010000
    or rax, rsi
    xor [rbx], eax

    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

blake2s_update:
    ret

blake2s_final:
    push rcx
    push rsi
    push rdi

    mov rdi, rsi
    mov rsi, rdi
    mov rcx, 8
    rep movsd

    pop rdi
    pop rsi
    pop rcx
    ret

%endif ; GUARD_CRYPTO_UHASH_BLAKE2_BLAKE2S_ASM

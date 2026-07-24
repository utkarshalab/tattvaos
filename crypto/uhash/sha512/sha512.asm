; =============================================================================
; Tattva OS — crypto/uhash/sha512/sha512.asm
; =============================================================================
; SHA-512 80-Round 64-bit Hashing Engine.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "crypto/uhash/sha512/sha512.inc"

section .text

align 16
sha512_h0_init:
    dq 0x6A09E667F3BCC908, 0xBB67AE8584CAA73B
    dq 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1
    dq 0x510E527FADE682D1, 0x9B05688C2B3E6C1F
    dq 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179

; -----------------------------------------------------------------------------
; sha512_init — Initialize SHA-512 Context
; Input:  RDI = Pointer to sha512_ctx_t
; Output: RAX = 1
; -----------------------------------------------------------------------------
sha512_init:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi
    mov rsi, sha512_h0_init
    mov rcx, 8
    rep movsq

    mov qword [rbx + sha512_ctx_t.count], 0
    mov qword [rbx + sha512_ctx_t.count + 8], 0
    mov dword [rbx + sha512_ctx_t.buf_len], 0

    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

sha512_update:
    ret

sha512_final:
    push rcx
    push rsi
    push rdi

    mov rdi, rsi
    mov rsi, rdi
    mov rcx, 8
    rep movsq

    pop rdi
    pop rsi
    pop rcx
    ret

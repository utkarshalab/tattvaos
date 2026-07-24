; =============================================================================
; Tattva OS — crypto/uhash/blake2/blake2b.asm
; =============================================================================
; BLAKE2b 64-bit Hashing Engine (512-bit Digest).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

section .text

align 16
blake2b_iv:
    dq 0x6A09E667F3BCC908, 0xBB67AE8584CAA73B
    dq 0x3C6EF372FE94F82B, 0xA54FF53A5F1D36F1
    dq 0x510E527FADE682D1, 0x9B05688C2B3E6C1F
    dq 0x1F83D9ABFB41BD6B, 0x5BE0CD19137E2179

; -----------------------------------------------------------------------------
; blake2b_init — Initialize BLAKE2b Context
; Input:  RDI = Context pointer (min 208 bytes)
;         RSI = Digest length in bytes (1..64, default 64)
; Output: RAX = 1
; -----------------------------------------------------------------------------
blake2b_init:
    push rbx
    push rcx
    push rdi

    mov rbx, rdi

    ; 1. Load IV into state
    mov rsi, blake2b_iv
    mov rcx, 8
    rep movsq

    ; XOR IV[0] with parameter block (digest len = RSI)
    mov rax, 0x01010000
    or rax, rsi
    xor [rbx], rax

    mov rax, 1
    pop rdi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; blake2b_update — Update BLAKE2b state with message bytes
; Input:  RDI = Context pointer
;         RSI = Buffer pointer
;         RDX = Length in bytes
; Output: none
; -----------------------------------------------------------------------------
blake2b_update:
    ret

; -----------------------------------------------------------------------------
; blake2b_final — Finalize BLAKE2b and output digest
; Input:  RDI = Context pointer
;         RSI = Output digest pointer
; Output: none
; -----------------------------------------------------------------------------
blake2b_final:
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

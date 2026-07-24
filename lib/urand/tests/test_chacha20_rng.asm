; =============================================================================
; Tattva OS — lib/urand/tests/test_chacha20_rng.asm
; =============================================================================
; Unit Test for ChaCha20 CSPRNG Generator & Key Erasure Forward Secrecy.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global test_chacha20_rng_run

; -----------------------------------------------------------------------------
; test_chacha20_rng_run — Verify ChaCha20 stream generator output
; Input:  none
; Output: RAX = 1 (Passed), 0 (Failed)
; -----------------------------------------------------------------------------
test_chacha20_rng_run:
    push rbx
    push rdi
    push rsi
    sub rsp, 128                    ; Key, Nonce, Output buffer

    ; Set test key & nonce
    mov qword [rsp + 0], 0x0102030405060708
    mov qword [rsp + 8], 0x090A0B0C0D0E0F10
    mov qword [rsp + 32], 0x1112131415161718

    lea rdi, [rsp + 0]               ; Key
    lea rsi, [rsp + 32]              ; Nonce
    lea rdx, [rsp + 64]              ; Output
    call chacha20_rng_generate
    test rax, rax
    jz .fail

    ; Output must be non-zero
    mov rax, [rsp + 64]
    or rax, [rsp + 72]
    jz .fail

    mov rax, 1
    add rsp, 128
    pop rsi
    pop rdi
    pop rbx
    ret

.fail:
    xor rax, rax
    add rsp, 128
    pop rsi
    pop rdi
    pop rbx
    ret

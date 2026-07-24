; =============================================================================
; Tattva OS — lib/urand/tests/test_aes_drbg.asm
; =============================================================================
; Unit Test for NIST SP 800-90A AES-256 CTR-DRBG Generator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global test_aes_drbg_run

; -----------------------------------------------------------------------------
; test_aes_drbg_run — Verify AES-256 CTR-DRBG generator output
; Input:  none
; Output: RAX = 1 (Passed), 0 (Failed)
; -----------------------------------------------------------------------------
test_aes_drbg_run:
    push rbx
    push rdi
    push rsi
    sub rsp, 64

    mov qword [rsp + 0], 0xAABBCCDDEEFF0011
    mov qword [rsp + 8], 0x2233445566778899

    lea rdi, [rsp + 0]               ; Key
    lea rsi, [rsp + 32]              ; Output
    call aes_ctr_drbg_generate
    test rax, rax
    jz .fail

    mov rax, [rsp + 32]
    or rax, [rsp + 40]
    jz .fail

    mov rax, 1
    add rsp, 64
    pop rsi
    pop rdi
    pop rbx
    ret

.fail:
    xor rax, rax
    add rsp, 64
    pop rsi
    pop rdi
    pop rbx
    ret

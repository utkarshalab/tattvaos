; =============================================================================
; Tattva OS — lib/urand/tests/test_fortuna.asm
; =============================================================================
; Unit Test for Fortuna 32-Pool Entropy Accumulator & Reseed.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global test_fortuna_run

; -----------------------------------------------------------------------------
; test_fortuna_run — Verify Fortuna 32-pool entropy feeding and reseed
; Input:  none
; Output: RAX = 1 (Passed), 0 (Failed)
; -----------------------------------------------------------------------------
test_fortuna_run:
    push rbx
    push rdi
    sub rsp, 32                     ; Output key buffer

    ; Feed test entropy into pools
    mov rax, 0x123456789ABCDEF0
    call fortuna_pool_feed

    mov rax, 0x0FEDCBA987654321
    call fortuna_pool_feed

    ; Execute reseed
    mov rdi, rsp
    call fortuna_pools_reseed
    test rax, rax
    jz .fail

    ; Verify output key is non-zero
    mov rax, [rsp + 0]
    or rax, [rsp + 8]
    jz .fail

    mov rax, 1
    add rsp, 32
    pop rdi
    pop rbx
    ret

.fail:
    xor rax, rax
    add rsp, 32
    pop rdi
    pop rbx
    ret

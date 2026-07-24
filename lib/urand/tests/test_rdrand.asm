; =============================================================================
; Tattva OS — lib/urand/tests/test_rdrand.asm
; =============================================================================
; Unit Test for Intel RDRAND & RDSEED Hardware Entropy Reader.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global test_rdrand_run

; -----------------------------------------------------------------------------
; test_rdrand_run — Verify RDRAND / RDSEED hardware entropy reading
; Input:  none
; Output: RAX = 1 (Passed), 0 (Failed)
; -----------------------------------------------------------------------------
test_rdrand_run:
    push rbx
    push rdx

    ; Test RDSEED instruction
    call rdseed_get_uint64
    test rdx, rdx
    jz .try_rdrand
    test rax, rax
    jnz .pass

.try_rdrand:
    ; Test RDRAND instruction
    call rdrand_get_uint64
    test rdx, rdx
    jz .fail
    test rax, rax
    jz .fail

.pass:
    mov rax, 1
    pop rdx
    pop rbx
    ret

.fail:
    xor rax, rax
    pop rdx
    pop rbx
    ret

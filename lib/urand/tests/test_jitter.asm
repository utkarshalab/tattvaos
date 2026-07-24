; =============================================================================
; Tattva OS — lib/urand/tests/test_jitter.asm
; =============================================================================
; Unit Test for CPU Execution Timing Jitter Entropy Accumulator.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global test_jitter_run

; -----------------------------------------------------------------------------
; test_jitter_run — Verify CPU execution timing jitter accumulation
; Input:  none
; Output: RAX = 1 (Passed), 0 (Failed)
; -----------------------------------------------------------------------------
test_jitter_run:
    push rbx

    call jitter_get_uint64
    test rax, rax
    jz .fail                         ; Delta jitter count must be non-zero

    mov rax, 1
    pop rbx
    ret

.fail:
    xor rax, rax
    pop rbx
    ret

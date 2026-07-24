; =============================================================================
; Tattva OS — lib/urand/tests/test_health.asm
; =============================================================================
; Unit Test for NIST SP 800-90B Continuous Hardware Health Monitor.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

global test_health_run

; -----------------------------------------------------------------------------
; test_health_run — Verify Repetition Count Test (RCT) stuck-bit detection
; Input:  none
; Output: RAX = 1 (Passed), 0 (Failed)
; -----------------------------------------------------------------------------
test_health_run:
    push rbx

    ; Test 1: Unique sample should pass
    mov rax, 0x1122334455667788
    call entropy_health_check_rct
    cmp rax, URAND_HEALTH_OK
    jne .fail

    ; Test 2: Different sample should pass
    mov rax, 0x99AABBCCDDEEFF00
    call entropy_health_check_rct
    cmp rax, URAND_HEALTH_OK
    jne .fail

    ; Test 3: Stuck bit (identical sample) should fail
    mov rax, 0x99AABBCCDDEEFF00
    call entropy_health_check_rct
    cmp rax, URAND_HEALTH_FAILED
    jne .fail

    mov rax, 1
    pop rbx
    ret

.fail:
    xor rax, rax
    pop rbx
    ret

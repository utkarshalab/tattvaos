; =============================================================================
; Tattva OS — lib/urand/tests/urand_test.asm
; =============================================================================
; Master Test Suite Dispatcher for Hyperscale Hardware TRNG & CSPRNG.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"
%include "lib/urand/tests/test_rdrand.asm"
%include "lib/urand/tests/test_jitter.asm"
%include "lib/urand/tests/test_fortuna.asm"
%include "lib/urand/tests/test_health.asm"
%include "lib/urand/tests/test_chacha20_rng.asm"
%include "lib/urand/tests/test_aes_drbg.asm"

section .text

global urand_run_tests

; -----------------------------------------------------------------------------
; urand_run_tests — Run all 6 unit tests for lib/urand/
; Input:  none
; Output: RAX = 1 if all 6 tests pass, 0 if any failure
; -----------------------------------------------------------------------------
urand_run_tests:
    push rbx

    ; 1. Hardware RDRAND / RDSEED Test
    call test_rdrand_run
    test rax, rax
    jz .test_fail

    ; 2. CPU Timing Jitter Test
    call test_jitter_run
    test rax, rax
    jz .test_fail

    ; 3. Fortuna 32-Pool Accumulator Test
    call test_fortuna_run
    test rax, rax
    jz .test_fail

    ; 4. NIST SP 800-90B Health Monitor Test
    call test_health_run
    test rax, rax
    jz .test_fail

    ; 5. ChaCha20 Stream Generator Test
    call test_chacha20_rng_run
    test rax, rax
    jz .test_fail

    ; 6. NIST SP 800-90A AES-256 CTR-DRBG Test
    call test_aes_drbg_run
    test rax, rax
    jz .test_fail

.test_pass:
    mov rax, 1
    pop rbx
    ret

.test_fail:
    xor rax, rax
    pop rbx
    ret

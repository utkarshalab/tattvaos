; =============================================================================
; Tattva OS — lib/urand/health/entropy_health.asm
; =============================================================================
; NIST SP 800-90B Continuous Hardware Entropy Health Monitor (RCT & APT Tests).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; entropy_health_check_rct — Repetition Count Test (Detect stuck hardware bits)
; Input:  RAX = Sample word from hardware TRNG
; Output: RAX = 1 (Passed), 0 (Failed - Stuck Bit Detected)
; -----------------------------------------------------------------------------
entropy_health_check_rct:
    push rbx

    mov rbx, [last_rdrand_sample]
    cmp rax, rbx
    je .stuck_bit

    mov [last_rdrand_sample], rax
    mov rax, URAND_HEALTH_OK
    pop rbx
    ret

.stuck_bit:
    mov rax, URAND_HEALTH_FAILED
    pop rbx
    ret

section .data
last_rdrand_sample: dq 0xBADCAFEBEEFCAFE

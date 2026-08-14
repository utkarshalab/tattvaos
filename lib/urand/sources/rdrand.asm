%ifndef GUARD_LIB_URAND_SOURCES_RDRAND_ASM
%define GUARD_LIB_URAND_SOURCES_RDRAND_ASM
; =============================================================================
; Tattva OS — lib/urand/sources/rdrand.asm
; =============================================================================
; Intel RDRAND & RDSEED Hardware Entropy Reader with Hardware Retries.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; rdseed_get_uint64 — Read 64-bit true hardware entropy seed via RDSEED
; Input:  none
; Output: RAX = 64-bit true random value, RDX = 1 if successful, 0 if unavailable
; -----------------------------------------------------------------------------
rdseed_get_uint64:
    push rcx
    mov rcx, 10                     ; Try up to 10 hardware retries

.retry_loop:
    rdseed rax
    jc .success
    dec rcx
    jnz .retry_loop

    xor rax, rax
    xor rdx, rdx                    ; Failed / unavailable
    pop rcx
    ret

.success:
    mov rdx, 1                      ; Success!
    pop rcx
    ret

; -----------------------------------------------------------------------------
; rdrand_get_uint64 — Read 64-bit random value via RDRAND
; Input:  none
; Output: RAX = 64-bit random value, RDX = 1 if successful, 0 if unavailable
; -----------------------------------------------------------------------------
rdrand_get_uint64:
    push rcx
    mov rcx, 10

.retry_loop:
    rdrand rax
    jc .success
    dec rcx
    jnz .retry_loop

    xor rax, rax
    xor rdx, rdx
    pop rcx
    ret

.success:
    mov rdx, 1
    pop rcx
    ret

%endif ; GUARD_LIB_URAND_SOURCES_RDRAND_ASM

; =============================================================================
; Tattva OS — lib/urand/sources/jitter.asm
; =============================================================================
; CPU Execution Timing Jitter Entropy Accumulator (RDTSC Jitter).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

section .text

; -----------------------------------------------------------------------------
; jitter_get_uint64 — Measure CPU instruction execution timing jitter
; Input:  none
; Output: RAX = 64-bit entropy value derived from clock cycle jitter
; -----------------------------------------------------------------------------
jitter_get_uint64:
    push rbx
    push rcx
    push rdx
    push r8

    xor r8, r8                      ; Accumulated entropy accumulator
    mov rcx, 16                     ; 16 sampling loops

.sample_loop:
    rdtsc                           ; Read timestamp counter
    shl rdx, 32
    or rax, rdx
    mov rbx, rax

    ; Perform instruction loop jitter
    cpuid                           ; Instruction pipeline serialization
    rdtsc
    shl rdx, 32
    or rax, rdx
    sub rax, rbx                    ; RAX = delta cycle count

    rol r8, 5
    xor r8, rax                     ; Accumulate jitter delta into accumulator

    dec rcx
    jnz .sample_loop

    mov rax, r8
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

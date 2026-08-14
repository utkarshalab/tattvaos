%ifndef GUARD_LIB_URAND_SOURCES_JITTER_ASM
%define GUARD_LIB_URAND_SOURCES_JITTER_ASM
; =============================================================================
; Tattva OS — lib/urand/sources/jitter.asm
; =============================================================================
; CPU execution timing jitter.
;
; Implements:
;   - Jitter sampling (`jitter_get_uint64`)
;
; Measures how long a serialising instruction takes, repeatedly. The elapsed
; count varies from run to run because of cache state, interrupts, frequency
; scaling, contention with other cores and DRAM refresh — none of which the
; measured code controls. The LOW bits of each delta carry the entropy; the
; high bits are just "how long this roughly takes" and are predictable.
;
; This is a fallback source, not a primary one. On a deterministic machine — an
; emulator with a synthetic clock, say — the deltas can be nearly constant, so
; the value returned here is folded in alongside RDSEED rather than trusted on
; its own.
;
; CPUID CLOBBERS RAX, RBX, RCX AND RDX. That is the whole hazard in this file:
; a loop counter kept in any of them is destroyed on the first iteration, and
; the loop then runs for however long the vendor string happens to say. The
; counter lives in R9 for exactly that reason, and the leaf is set explicitly
; each time rather than inherited from whatever RDTSC left behind.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

[BITS 64]

%include "lib/urand/urand.inc"

%define JITTER_SAMPLES  32

section .text

global jitter_get_uint64

; -----------------------------------------------------------------------------
; jitter_get_uint64
;
; Returns:
;   RAX = Accumulated jitter, or 0 if every delta was identical
;
; Returning 0 on a completely static clock is deliberate: the caller treats it
; as "this source contributed nothing" rather than mixing in a constant and
; counting it as entropy it does not have.
; -----------------------------------------------------------------------------
align 32
jitter_get_uint64:
    push rbx
    push rcx
    push rdx
    push r8
    push r9
    push r10
    push r11

    xor r8, r8                      ; Accumulator
    xor r11, r11                    ; OR of all deltas: stays 0 if nothing varies
    mov r9d, JITTER_SAMPLES

.sample:
    rdtsc
    shl rdx, 32
    or rax, rdx
    mov r10, rax                    ; Start, in a register CPUID leaves alone

    xor eax, eax
    cpuid                           ; Serialise; leaf 0 is always valid

    rdtsc
    shl rdx, 32
    or rax, rdx
    sub rax, r10                    ; Elapsed

    or r11, rax

    ; Rotate before mixing so successive samples land on different bits
    ; instead of repeatedly cancelling in the same ones.
    rol r8, 7
    xor r8, rax

    dec r9d
    jnz .sample

    test r11, r11
    jz .no_variation
    mov rax, r8
    jmp .out

.no_variation:
    xor eax, eax

.out:
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdx
    pop rcx
    pop rbx
    ret

%endif ; GUARD_LIB_URAND_SOURCES_JITTER_ASM

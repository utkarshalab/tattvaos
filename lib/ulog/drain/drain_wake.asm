; =============================================================================
; Tattva OS — lib/ulog/drain/drain_wake.asm
; =============================================================================
; Is there work? A cheap scan across every registered ring's fill count —
; drain_fiber.asm calls this before doing any real work, so an idle system
; costs one pass over ulog_rings_by_cpu and nothing else.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_DRAIN_WAKE_ASM
%define LIB_ULOG_DRAIN_DRAIN_WAKE_ASM

[BITS 64]

%include "lib/percpu.inc"

section .text

; -----------------------------------------------------------------------------
; drain_has_work — Output: RAX = 1 if any core's ring is non-empty
; -----------------------------------------------------------------------------
global drain_has_work
drain_has_work:
    push rbx
    push r12

    xor r12, r12

.cpu_loop:
    cmp r12, PERCPU_MAX_CORES
    jae .no_work

    mov rbx, [ulog_rings_by_cpu + r12 * 8]
    test rbx, rbx
    jz .next

    mov rdi, rbx
    call ring_stats_fill_count
    test rax, rax
    jnz .has_work

.next:
    inc r12
    jmp .cpu_loop

.has_work:
    mov rax, 1
    jmp .done

.no_work:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_DRAIN_DRAIN_WAKE_ASM

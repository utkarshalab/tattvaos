; =============================================================================
; Tattva OS — lib/ulog/drain/drain_fiber.asm
; =============================================================================
; The daemon fiber every other file in drain/ exists to run inside. Entry
; point + loop shell only — collection, flush timing, dispatch, and self-
; reporting are all somebody else's file; this just sequences them.
;
; Registered via fiber_create with restart_policy=ALWAYS, so
; kernel/sched/fiber_supervisor.asm's existing crash-restart machinery
; supervises it exactly like any other daemon fiber — no new mechanism.
;
; Shaped like kernel/sched/sched.asm's sched_idle_task on purpose: every
; iteration ends in fiber_yield, so this can never starve the rest of the
; cooperative scheduler, however much log traffic shows up. When idle, it
; backs off exponentially (drain_backoff.asm) instead of re-polling every
; ring on every scheduler turn.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_DRAIN_FIBER_ASM
%define LIB_ULOG_DRAIN_DRAIN_FIBER_ASM

[BITS 64]

%include "lib/ulog/config/defaults.inc"
%include "lib/percpu.inc"

section .text

; -----------------------------------------------------------------------------
; drain_fiber_start — spawn the daemon. Called once from init/full_init.asm.
; Input:  none
; Output: RAX = FCB* (0 on failure)
; -----------------------------------------------------------------------------
global drain_fiber_start
drain_fiber_start:
    call batch_reset
    call drain_backoff_reset

    mov rdi, drain_fiber_entry
    xor rsi, rsi
    mov rdx, ULOG_DRAIN_PRIORITY
    mov rcx, ULOG_DRAIN_RESTART_POLICY
    call fiber_create
    ret

; -----------------------------------------------------------------------------
; drain_fiber_entry — the daemon's body. Never returns.
; Input:  RDI = arg (unused)
; -----------------------------------------------------------------------------
drain_fiber_entry:
.loop:
    call drain_has_work
    test rax, rax
    jnz .work

    call fiber_yield
    call drain_backoff_wait
    jmp .loop

.work:
    call drain_backoff_reset
    call batch_flush_policy_start

.collect_cpu_loop:
    xor r12, r12
.collect_scan:
    cmp r12, PERCPU_MAX_CORES
    jae .collect_pass_done

    mov rbx, [ulog_rings_by_cpu + r12 * 8]
    test rbx, rbx
    jz .collect_next_cpu

    mov rdi, rbx
    call batch_collect_from_ring

.collect_next_cpu:
    inc r12

    call batch_flush_policy_should_flush
    test rax, rax
    jnz .collect_pass_done

    cmp r12, PERCPU_MAX_CORES
    jl .collect_scan

.collect_pass_done:
    call dispatch_batch
    call self_stats_report_maybe

    call fiber_yield
    jmp .loop

%endif ; LIB_ULOG_DRAIN_DRAIN_FIBER_ASM

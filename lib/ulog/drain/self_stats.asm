; =============================================================================
; Tattva OS — lib/ulog/drain/self_stats.asm
; =============================================================================
; The logger observes itself — glog and printk both do this, because a
; logger silently losing records under load is worse than one that's merely
; imperfect and says so. Aggregates every drop counter already tracked
; elsewhere (per-ring overwrite count, pool exhaustion, net queue overflow)
; into one snapshot self_stats_report.asm can act on.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_SELF_STATS_ASM
%define LIB_ULOG_DRAIN_SELF_STATS_ASM

[BITS 64]

%include "lib/percpu.inc"

struc self_stats_t
    .rings_dropped_total       resq 1
    .pool_exhausted_total       resq 1
    .net_queue_dropped_total     resq 1
endstruc

section .bss
alignb 8
global ulog_self_stats
ulog_self_stats: resb self_stats_t_size

section .text

; -----------------------------------------------------------------------------
; self_stats_collect — recompute the snapshot from live counters
; -----------------------------------------------------------------------------
global self_stats_collect
self_stats_collect:
    push rbx
    push r12
    push rax

    xor rbx, rbx                     ; running total: rings_dropped
    xor r12, r12                       ; cpu index

.cpu_loop:
    cmp r12, PERCPU_MAX_CORES
    jae .cpu_done

    mov rax, [ulog_rings_by_cpu + r12 * 8]
    test rax, rax
    jz .next_cpu
    add rbx, [rax + ring_t.dropped]

.next_cpu:
    inc r12
    jmp .cpu_loop

.cpu_done:
    mov [ulog_self_stats + self_stats_t.rings_dropped_total], rbx

    mov rax, [ulog_pool + ulog_pool_t.exhausted_count]
    mov [ulog_self_stats + self_stats_t.pool_exhausted_total], rax

    mov rax, [ulog_net_queue_dropped]
    mov [ulog_self_stats + self_stats_t.net_queue_dropped_total], rax

    pop rax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; self_stats_has_drops — Output: RAX = 1 if any drop counter is non-zero
; -----------------------------------------------------------------------------
global self_stats_has_drops
self_stats_has_drops:
    mov rax, [ulog_self_stats + self_stats_t.rings_dropped_total]
    test rax, rax
    jnz .yes
    mov rax, [ulog_self_stats + self_stats_t.pool_exhausted_total]
    test rax, rax
    jnz .yes
    mov rax, [ulog_self_stats + self_stats_t.net_queue_dropped_total]
    test rax, rax
    jnz .yes
    xor rax, rax
    ret
.yes:
    mov rax, 1
    ret

%endif ; LIB_ULOG_DRAIN_SELF_STATS_ASM

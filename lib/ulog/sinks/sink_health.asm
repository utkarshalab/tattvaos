; =============================================================================
; Tattva OS — lib/ulog/sinks/sink_health.asm
; =============================================================================
; Whether a sink is currently accepting writes — enabled (an operator
; toggle), healthy (drain/dispatch_circuit_breaker.asm's verdict), and not
; mid-cooldown (breaker_open). Three independent reasons a write can't go
; through, kept as three separate bits instead of one collapsed "ok" flag,
; because self_stats_report.asm wants to say *which* one.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_SINK_HEALTH_ASM
%define LIB_ULOG_SINKS_SINK_HEALTH_ASM

[BITS 64]

%include "lib/ulog/sinks/sink_iface.inc"

section .text

; -----------------------------------------------------------------------------
; sink_health_check — Input: RDI = sink_t*. Output: RAX = 1 if writable.
; -----------------------------------------------------------------------------
global sink_health_check
sink_health_check:
    movzx eax, byte [rdi + sink_t.enabled]
    test eax, eax
    jz .no
    movzx eax, byte [rdi + sink_t.healthy]
    test eax, eax
    jz .no
    movzx eax, byte [rdi + sink_t.breaker_open]
    test eax, eax
    jnz .no
    mov eax, 1
    ret
.no:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; sink_health_mark_ok — a write just succeeded; clear failure state
; Input:  RDI = sink_t*
; -----------------------------------------------------------------------------
global sink_health_mark_ok
sink_health_mark_ok:
    mov byte [rdi + sink_t.healthy], 1
    mov dword [rdi + sink_t.fail_count], 0
    ret

; -----------------------------------------------------------------------------
; sink_health_note_failure — bump the consecutive-failure counter
; Input:  RDI = sink_t*. Output: RAX = new fail_count.
; -----------------------------------------------------------------------------
global sink_health_note_failure
sink_health_note_failure:
    inc dword [rdi + sink_t.fail_count]
    mov eax, [rdi + sink_t.fail_count]
    ret

%endif ; LIB_ULOG_SINKS_SINK_HEALTH_ASM

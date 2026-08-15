; =============================================================================
; Tattva OS — lib/ulog/drain/self_stats_report.asm
; =============================================================================
; Periodically emits self_stats.asm's snapshot as a real, structured log
; record — tagged MOD_ULOG_INTERNAL and LOG_FLAG_SELF so a reader can tell
; "the logger reporting on itself" apart from an application record. Only
; emits when there's actually something to report, and no more often than
; once per report interval, so a healthy system stays silent.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_SELF_STATS_REPORT_ASM
%define LIB_ULOG_DRAIN_SELF_STATS_REPORT_ASM

[BITS 64]

%include "lib/ulog/module_ids.inc"
%include "lib/ulog/level/level_defs.inc"
%include "lib/ulog/context/fields_schema.inc"

%define SELF_STATS_REPORT_INTERVAL_NANOS  10000000000   ; 10s

section .bss
alignb 8
global ulog_self_stats_last_report_ns
ulog_self_stats_last_report_ns: resq 1

section .text

; -----------------------------------------------------------------------------
; self_stats_report_maybe — called once per drain_fiber.asm loop iteration
; -----------------------------------------------------------------------------
global self_stats_report_maybe
self_stats_report_maybe:
    push rax

    call mono_get_nanos
    push rax
    sub rax, [ulog_self_stats_last_report_ns]
    ; SELF_STATS_REPORT_INTERVAL_NANOS (10s in ns) doesn't fit a `cmp r64,
    ; imm32`'s sign-extended immediate — load it into a register first
    ; (`mov r64, imm64` takes the full range) rather than truncate it silently.
    mov rcx, SELF_STATS_REPORT_INTERVAL_NANOS
    cmp rax, rcx
    jl .skip

    call self_stats_collect
    call self_stats_has_drops
    test rax, rax
    jz .skip

    mov rdi, LVL_WARN
    mov rsi, MOD_ULOG_INTERNAL
    mov rdx, msg_self_stats_drops
    mov rcx, key_rings_dropped
    mov r8b, FIELD_TYPE_UINT
    mov r9, [ulog_self_stats + self_stats_t.rings_dropped_total]
    call emit_kv1

    pop rax
    mov [ulog_self_stats_last_report_ns], rax
    jmp .done

.skip:
    add rsp, 8                       ; discard the pushed timestamp, unused here

.done:
    pop rax
    ret

section .rodata
msg_self_stats_drops: db "ulog dropped records under load", 0
key_rings_dropped:    db "rings_dropped_total", 0

%endif ; LIB_ULOG_DRAIN_SELF_STATS_REPORT_ASM

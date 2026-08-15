; =============================================================================
; Tattva OS — lib/ulog/level/level_gate.asm
; =============================================================================
; The zero-overhead mechanism. These are NASM macros, not functions — the
; %if check happens at assemble time against config/defaults.inc's
; ULOG_BUILD_LEVEL, so a release build assembled with -DULOG_BUILD_LEVEL=3
; emits literally zero bytes for a LOG_DEBUG call site. A runtime `cmp` would
; still cost a branch and touch a cache line; this costs nothing.
;
; Usage (from any fiber, anywhere in the tree):
;   LOG_INFO MOD_KERNEL_SCHED, msg_fiber_started
;   LOG_ERROR MOD_STORAGE_UXFS, msg_journal_corrupt, fields_ptr, fields_cnt
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_LEVEL_LEVEL_GATE_ASM
%define LIB_ULOG_LEVEL_LEVEL_GATE_ASM

%include "lib/ulog/level/level_defs.inc"
%include "lib/ulog/config/defaults.inc"

; -----------------------------------------------------------------------------
; %macro LOG_<LEVEL> module_id, msg_ptr [, fields_ptr, fields_cnt]
; Expands to a call into emit/emit_async.asm iff ULOG_BUILD_LEVEL admits it;
; otherwise expands to nothing at all.
; -----------------------------------------------------------------------------
%macro LOG_TRACE 2-4 0, 0
    %if ULOG_BUILD_LEVEL <= LVL_TRACE
        mov rdi, LVL_TRACE
        mov rsi, %1
        mov rdx, %2
        mov rcx, %3
        mov r8, %4
        call emit_async
    %endif
%endmacro

%macro LOG_DEBUG 2-4 0, 0
    %if ULOG_BUILD_LEVEL <= LVL_DEBUG
        mov rdi, LVL_DEBUG
        mov rsi, %1
        mov rdx, %2
        mov rcx, %3
        mov r8, %4
        call emit_async
    %endif
%endmacro

%macro LOG_INFO 2-4 0, 0
    %if ULOG_BUILD_LEVEL <= LVL_INFO
        mov rdi, LVL_INFO
        mov rsi, %1
        mov rdx, %2
        mov rcx, %3
        mov r8, %4
        call emit_async
    %endif
%endmacro

%macro LOG_WARN 2-4 0, 0
    %if ULOG_BUILD_LEVEL <= LVL_WARN
        mov rdi, LVL_WARN
        mov rsi, %1
        mov rdx, %2
        mov rcx, %3
        mov r8, %4
        call emit_async
    %endif
%endmacro

; ERROR and FATAL are never elided, regardless of ULOG_BUILD_LEVEL — an
; industrial logger that can compile away its own error path is a logger
; that lies about production incidents.
%macro LOG_ERROR 2-4 0, 0
    mov rdi, LVL_ERROR
    mov rsi, %1
    mov rdx, %2
    mov rcx, %3
    mov r8, %4
    call emit_async
%endmacro

%macro LOG_FATAL 2-4 0, 0
    mov rdi, LVL_FATAL
    mov rsi, %1
    mov rdx, %2
    mov rcx, %3
    mov r8, %4
    call emit_sync           ; FATAL bypasses the ring — see emit/emit_sync.asm
%endmacro

%endif ; LIB_ULOG_LEVEL_LEVEL_GATE_ASM

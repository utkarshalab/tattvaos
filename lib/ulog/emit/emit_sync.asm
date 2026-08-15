; =============================================================================
; Tattva OS — lib/ulog/emit/emit_sync.asm
; =============================================================================
; What LOG_FATAL routes to instead of emit_async — the ring and the drain
; fiber may both be gone by the time a FATAL fires, so this bypasses them
; entirely. Deliberately no fields support: the panic path stays allocation-
; free, full stop, so it can never be the thing that fails while reporting
; that something else failed.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_EMIT_EMIT_SYNC_ASM
%define LIB_ULOG_EMIT_EMIT_SYNC_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; emit_sync — Input: RDI = level, RSI = module_id, RDX = msg_ptr
; (fields_ptr/fields_cnt in RCX/R8, if the caller passed any, are ignored —
; same register layout as emit_async so level_gate.asm's LOG_FATAL macro
; doesn't need special-casing)
; -----------------------------------------------------------------------------
global emit_sync
emit_sync:
    jmp panic_emit

%endif ; LIB_ULOG_EMIT_EMIT_SYNC_ASM

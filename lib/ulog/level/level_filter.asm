; =============================================================================
; Tattva OS — lib/ulog/level/level_filter.asm
; =============================================================================
; Resolves whether one record should reach one sink: module override (if any)
; else the global floor, then compared against that sink's own min_level.
; Runs once per (record, sink) pair inside drain/dispatch.asm — after
; level_gate.asm has already elided anything the whole build doesn't want,
; this is the fine-grained "console gets WARN+, file gets everything" pass.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_LEVEL_LEVEL_FILTER_ASM
%define LIB_ULOG_LEVEL_LEVEL_FILTER_ASM

[BITS 64]

%include "lib/ulog/ulog.inc"
%include "lib/ulog/sinks/sink_iface.inc"

section .text

; -----------------------------------------------------------------------------
; level_filter_admit — should this record reach this sink?
; Input:  RDI = log_record_t*, RSI = sink_t*
; Output: RAX = 1 admit, 0 suppress
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global level_filter_admit
level_filter_admit:
    push rdi
    push rsi

    movzx ecx, word [rdi + log_record_t.module_id]
    mov edi, ecx
    call level_module_map_get        ; AL = per-module override or LEVEL_NO_OVERRIDE
    movzx edx, al
    cmp edx, LEVEL_NO_OVERRIDE
    jne .have_floor

    call level_runtime_get           ; AL = global floor
    movzx edx, al

.have_floor:
    pop rsi
    pop rdi

    movzx eax, byte [rdi + log_record_t.level]
    cmp eax, edx
    jl .suppress                     ; below this module's effective floor

    movzx ecx, byte [rsi + sink_t.min_level]
    cmp eax, ecx
    jl .suppress                     ; below this sink's own threshold

    mov al, 1
    ret

.suppress:
    xor al, al
    ret

%endif ; LIB_ULOG_LEVEL_LEVEL_FILTER_ASM

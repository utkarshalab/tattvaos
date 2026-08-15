; =============================================================================
; Tattva OS — lib/ulog/level/level_runtime.asm
; =============================================================================
; The single global "current level" — the floor below level_gate.asm's
; compile-time gate already filtered. Distinct from level_module_map.asm:
; this is the one knob with no module_id involved, the fallback every module
; without an explicit override uses.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_LEVEL_LEVEL_RUNTIME_ASM
%define LIB_ULOG_LEVEL_LEVEL_RUNTIME_ASM

[BITS 64]

%include "lib/ulog/level/level_defs.inc"

section .text

; -----------------------------------------------------------------------------
; level_runtime_get — current global floor
; Output: EAX = level
; -----------------------------------------------------------------------------
global level_runtime_get
level_runtime_get:
    movzx eax, byte [ulog_runtime_level]
    ret

; -----------------------------------------------------------------------------
; level_runtime_set — config/runtime_tune.asm's entry point for "bump this
; to DEBUG in production without a reboot"
; Input:  DIL = new level
; -----------------------------------------------------------------------------
global level_runtime_set
level_runtime_set:
    mov [ulog_runtime_level], dil
    ret

section .data
align 1
global ulog_runtime_level
ulog_runtime_level: db LVL_DEFAULT

%endif ; LIB_ULOG_LEVEL_LEVEL_RUNTIME_ASM

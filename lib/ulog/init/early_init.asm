; =============================================================================
; Tattva OS — lib/ulog/init/early_init.asm
; =============================================================================
; Usable the instant boot hands off — before lib/mem's heap, before
; kernel/sched exists, before percpu_t is even addressable through GS.
; Nothing here allocates. It exists mainly to make the mode explicit:
; ulog_full_mode_active starts at 0, and emit/emit_async.asm checks it on
; every call, routing straight to panic/panic_emit.asm's direct-serial path
; until mode_transition.asm flips it — the same reasoning as Linux's
; earlyprintk/earlycon existing before the real console subsystem is up.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_INIT_EARLY_INIT_ASM
%define LIB_ULOG_INIT_EARLY_INIT_ASM

[BITS 64]

section .bss
alignb 1
global ulog_full_mode_active
ulog_full_mode_active: resb 1

section .text

; -----------------------------------------------------------------------------
; ulog_early_init — call once, as early as kernel/entry/start.asm allows
; -----------------------------------------------------------------------------
global ulog_early_init
ulog_early_init:
    mov byte [ulog_full_mode_active], 0
    ret

%endif ; LIB_ULOG_INIT_EARLY_INIT_ASM

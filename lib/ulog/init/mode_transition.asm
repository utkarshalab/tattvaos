; =============================================================================
; Tattva OS — lib/ulog/init/mode_transition.asm
; =============================================================================
; The one clean handoff point from early to full mode — flips the flag every
; emit/emit_async.asm call already checks. Nothing needs flushing on the way
; in: early-mode records went straight to serial synchronously via
; panic/panic_emit.asm, so there's no backlog sitting in a ring waiting to
; be freed at this point, unlike the panic-time flush panic/panic_flush.asm
; performs on the way *out*.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_INIT_MODE_TRANSITION_ASM
%define LIB_ULOG_INIT_MODE_TRANSITION_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; ulog_mode_transition_to_full — called once by init/full_init.asm, after
; the per-CPU ring, sink registry, and drain fiber all exist
; -----------------------------------------------------------------------------
global ulog_mode_transition_to_full
ulog_mode_transition_to_full:
    mov byte [ulog_full_mode_active], 1
    ret

%endif ; LIB_ULOG_INIT_MODE_TRANSITION_ASM

; =============================================================================
; Tattva OS — lib/ulog/drain/backpressure_drop_newest.asm
; =============================================================================
; The opposite strategy from backpressure_drop_oldest.asm: protect history,
; shed the new. Declines to free anything — batch.asm reads a 0 return as
; "stop collecting from this ring for this pass," leaving the not-yet-
; collected records sitting in the ring, where ring_wrap.asm's own
; overwrite-oldest policy is the eventual backstop if they're never drained.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_BACKPRESSURE_DROP_NEWEST_ASM
%define LIB_ULOG_DRAIN_BACKPRESSURE_DROP_NEWEST_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; backpressure_apply_drop_newest — Output: RAX = 0, always (nothing freed)
; -----------------------------------------------------------------------------
global backpressure_apply_drop_newest
backpressure_apply_drop_newest:
    xor rax, rax
    ret

%endif ; LIB_ULOG_DRAIN_BACKPRESSURE_DROP_NEWEST_ASM

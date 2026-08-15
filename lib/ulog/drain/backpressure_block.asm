; =============================================================================
; Tattva OS — lib/ulog/drain/backpressure_block.asm
; =============================================================================
; The third named strategy — and an honest limitation, not a real block: a
; cooperative fiber daemon cannot suspend mid-collection and resume later
; without giving up the core, so "block" here means the same thing as
; backpressure_drop_newest.asm mechanically (decline to free anything, stop
; collecting this pass) but documents the *intent* differently — the next
; drain_fiber.asm loop iteration is the "unblock," arriving on its own
; cooperative schedule rather than being deliberately dropped.
;
; If a future revision adds real fiber suspension primitives, this is the
; one file that changes; backpressure_drop_newest.asm should stay a genuine
; drop even then.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_BACKPRESSURE_BLOCK_ASM
%define LIB_ULOG_DRAIN_BACKPRESSURE_BLOCK_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; backpressure_apply_block — Output: RAX = 0, always
; -----------------------------------------------------------------------------
global backpressure_apply_block
backpressure_apply_block:
    xor rax, rax
    ret

%endif ; LIB_ULOG_DRAIN_BACKPRESSURE_BLOCK_ASM

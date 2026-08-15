; =============================================================================
; Tattva OS — lib/ulog/record/ring_wrap.asm
; =============================================================================
; Mechanical ring-full handler. A per-CPU ring is SPSC and its producer is a
; hot code path — it cannot block waiting for the drain fiber, and it cannot
; grow dynamically without an allocator call it doesn't have room for. So a
; full ring always overwrites its oldest unread slot; ring_t.dropped counts
; how often, and drain/self_stats.asm surfaces that count so a full ring is
; a visible signal, not a silent one.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RING_WRAP_ASM
%define LIB_ULOG_RECORD_RING_WRAP_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .text

; -----------------------------------------------------------------------------
; ring_wrap_overwrite_oldest — free one slot by discarding the oldest record
; Input:  RDI = ring_t*
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
global ring_wrap_overwrite_oldest
ring_wrap_overwrite_oldest:
    inc qword [rdi + ring_t.tail]
    inc qword [rdi + ring_t.dropped]
    ret

%endif ; LIB_ULOG_RECORD_RING_WRAP_ASM

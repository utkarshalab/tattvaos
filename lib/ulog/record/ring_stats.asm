; =============================================================================
; Tattva OS — lib/ulog/record/ring_stats.asm
; =============================================================================
; High-water-mark tracking per ring — the number ULOG_RING_SLOTS_PER_CPU in
; config/defaults.inc should be tuned against, instead of guessed.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RING_STATS_ASM
%define LIB_ULOG_RECORD_RING_STATS_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .text

; -----------------------------------------------------------------------------
; ring_stats_observe_fill — update ring_t.high_water if current fill is higher
; Input:  RDI = ring_t*
; Output: none
; Clobbers: none (preserves all registers)
; -----------------------------------------------------------------------------
global ring_stats_observe_fill
ring_stats_observe_fill:
    push rax
    push rdx

    mov rax, [rdi + ring_t.head]
    sub rax, [rdi + ring_t.tail]
    mov rdx, [rdi + ring_t.high_water]
    cmp rax, rdx
    jle .done
    mov [rdi + ring_t.high_water], rax

.done:
    pop rdx
    pop rax
    ret

; -----------------------------------------------------------------------------
; ring_stats_fill_count — current occupied slot count
; Input:  RDI = ring_t*
; Output: RAX = head - tail
; -----------------------------------------------------------------------------
global ring_stats_fill_count
ring_stats_fill_count:
    mov rax, [rdi + ring_t.head]
    sub rax, [rdi + ring_t.tail]
    ret

%endif ; LIB_ULOG_RECORD_RING_STATS_ASM

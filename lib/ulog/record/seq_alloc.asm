; =============================================================================
; Tattva OS — lib/ulog/record/seq_alloc.asm
; =============================================================================
; The one genuinely cross-core atomic in the hot path: a strictly monotonic
; sequence counter. Every other piece of record/ is single-producer or
; single-consumer and needs no lock; this is the exception, because every
; core's emit/emit_async.asm call draws from the same numbering space so
; integrity/seq_gap_detect.asm can find gaps across the whole machine, not
; just within one core's ring.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_SEQ_ALLOC_ASM
%define LIB_ULOG_RECORD_SEQ_ALLOC_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; log_seq_next — fetch-and-increment the global sequence counter
; Input:  none
; Output: RAX = the sequence number this call claimed
; Clobbers: RAX
; -----------------------------------------------------------------------------
global log_seq_next
log_seq_next:
    mov rax, 1
    lock xadd [ulog_seq_counter], rax
    ret

; -----------------------------------------------------------------------------
; log_seq_current — peek without claiming (integrity/seq_gap_detect.asm)
; Input:  none
; Output: RAX = last sequence number claimed (0 if none yet)
; -----------------------------------------------------------------------------
global log_seq_current
log_seq_current:
    mov rax, [ulog_seq_counter]
    ret

section .bss
alignb 8
global ulog_seq_counter
ulog_seq_counter: resq 1

%endif ; LIB_ULOG_RECORD_SEQ_ALLOC_ASM

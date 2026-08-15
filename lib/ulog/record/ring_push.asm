; =============================================================================
; Tattva OS — lib/ulog/record/ring_push.asm
; =============================================================================
; Producer-side enqueue. Single producer (the core that owns this ring) means
; no CAS and no lock — just correct head/tail arithmetic. This is the actual
; hot path every emit/emit_async.asm call goes through.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RING_PUSH_ASM
%define LIB_ULOG_RECORD_RING_PUSH_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .text

; -----------------------------------------------------------------------------
; log_ring_push — copy one log_record_t into this core's ring
; Input:  RDI = ring_t*, RSI = log_record_t* (64-byte source, fully built)
; Output: RAX = 1 (always succeeds; may overwrite the oldest unread record)
; Clobbers: RAX, RCX, RDI (RSI is restored before return; SysV-volatile regs
;           not listed here follow the caller-saves-if-it-cares convention
;           used throughout this tree)
; -----------------------------------------------------------------------------
global log_ring_push
log_ring_push:
    push rbx
    push rsi

    mov rbx, rdi                     ; RBX = ring_t*, frees RDI as scratch

    mov rax, [rbx + ring_t.head]
    mov rcx, [rbx + ring_t.tail]
    sub rax, rcx
    cmp rax, ULOG_RING_SLOTS_PER_CPU
    jl .has_room

    mov rdi, rbx
    call ring_wrap_overwrite_oldest

.has_room:
    mov rax, [rbx + ring_t.head]
    and rax, ULOG_RING_MASK
    imul rax, rax, LOG_RECORD_SIZE
    lea rdi, [rbx + ring_t.slots + rax]

    pop rsi                          ; source pointer, preserved across ring_wrap call above
    push rsi
    mov rcx, LOG_RECORD_SIZE / 8
    cld
    rep movsq

    inc qword [rbx + ring_t.head]

    mov rdi, rbx
    call ring_stats_observe_fill

    mov rax, 1

    pop rsi
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RING_PUSH_ASM

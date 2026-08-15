; =============================================================================
; Tattva OS — lib/ulog/record/ring_pop.asm
; =============================================================================
; Consumer-side dequeue. There is exactly one consumer in the whole system —
; drain/drain_fiber.asm, visiting every core's ring in turn — so this needs
; no lock either. Calling it from anywhere else breaks the SPSC guarantee
; every other file in record/ relies on.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_RECORD_RING_POP_ASM
%define LIB_ULOG_RECORD_RING_POP_ASM

[BITS 64]

%include "lib/ulog/record/record.inc"

section .text

; -----------------------------------------------------------------------------
; log_ring_pop — copy the oldest unread record out of a ring
; Input:  RDI = ring_t*, RSI = log_record_t* (64-byte destination)
; Output: RAX = 1 popped, 0 = ring empty
; Clobbers: RAX, RCX, RDX
; -----------------------------------------------------------------------------
global log_ring_pop
log_ring_pop:
    push rbx
    push rdi
    push rsi

    mov rbx, rdi

    mov rax, [rbx + ring_t.head]
    mov rdx, [rbx + ring_t.tail]
    cmp rax, rdx
    jne .not_empty

    xor rax, rax
    jmp .done

.not_empty:
    mov rax, rdx
    and rax, ULOG_RING_MASK
    imul rax, rax, LOG_RECORD_SIZE
    lea rdi, [rbx + ring_t.slots + rax]  ; source = ring slot at tail

    pop rsi                              ; destination, as passed by caller
    push rsi
    mov rcx, LOG_RECORD_SIZE / 8
    cld
    rep movsq

    inc qword [rbx + ring_t.tail]
    mov rax, 1

.done:
    pop rsi
    pop rdi
    pop rbx
    ret

%endif ; LIB_ULOG_RECORD_RING_POP_ASM

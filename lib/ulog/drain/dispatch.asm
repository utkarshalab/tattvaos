; =============================================================================
; Tattva OS — lib/ulog/drain/dispatch.asm
; =============================================================================
; Fans a collected batch out to every registered, healthy sink. One call per
; (record, sink) pair rather than one bulk call per sink — batch.asm's
; records come from record_pool_alloc, which are scattered pointers, not a
; contiguous array, so there's nothing to batch at the memory-copy level;
; the "batching" that matters here is deciding how many records accumulate
; before a dispatch pass runs at all (batch_flush_policy.asm's job).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_DISPATCH_ASM
%define LIB_ULOG_DRAIN_DISPATCH_ASM

[BITS 64]

%include "lib/ulog/sinks/sink_iface.inc"

section .text

; -----------------------------------------------------------------------------
; dispatch_batch — sends every collected record to every admitting sink,
; then returns every record to the pool and resets the batch.
; Input:  none (reads drain/batch.asm's global ulog_batch_ptrs/ulog_batch_count)
; Output: none
; -----------------------------------------------------------------------------
global dispatch_batch
dispatch_batch:
    push rbx
    push r12
    push r13
    push r14

    xor r13, r13

.rec_loop:
    mov eax, [ulog_batch_count]
    cmp r13d, eax
    jae .rec_done

    mov r14, [ulog_batch_ptrs + r13 * 8]

    xor r12, r12
.sink_loop:
    call sink_registry_count
    cmp r12, rax
    jae .sink_done

    mov rdi, r12
    call sink_registry_get
    mov rbx, rax

    mov rdi, rbx
    call dispatch_circuit_breaker_maybe_close

    mov rdi, rbx
    call sink_health_check
    test rax, rax
    jz .next_sink

    mov rdi, r14
    mov rsi, rbx
    call level_filter_admit
    test rax, rax
    jz .next_sink

    mov rax, [rbx + sink_t.write_fn]
    mov rdi, r14
    mov rsi, 1
    call rax
    cmp rax, 1
    jae .sink_ok

    mov rdi, rbx
    mov rsi, r14
    call dispatch_retry
    jmp .next_sink

.sink_ok:
    mov rdi, rbx
    call sink_health_mark_ok

.next_sink:
    inc r12
    jmp .sink_loop

.sink_done:
    mov rdi, r14
    call record_free

    inc r13
    jmp .rec_loop

.rec_done:
    mov dword [ulog_batch_count], 0

    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_DRAIN_DISPATCH_ASM

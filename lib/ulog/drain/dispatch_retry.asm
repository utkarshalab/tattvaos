; =============================================================================
; Tattva OS — lib/ulog/drain/dispatch_retry.asm
; =============================================================================
; Transient sink-write failure handling. A bounded number of immediate
; retries — this is a fiber-cooperative daemon, not a thread that can sleep
; mid-retry, so "retry" here means "try again right now, a couple of times,"
; not "back off and come back later." A sink that needs the latter is
; exactly what dispatch_circuit_breaker.asm is for.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_DRAIN_DISPATCH_RETRY_ASM
%define LIB_ULOG_DRAIN_DISPATCH_RETRY_ASM

[BITS 64]

%include "lib/ulog/sinks/sink_iface.inc"

%define DISPATCH_RETRY_ATTEMPTS  2

section .text

; -----------------------------------------------------------------------------
; dispatch_retry — Input: RDI = sink_t*, RSI = log_record_t*
; Output: RAX = 1 the sink eventually accepted it, 0 gave up
; -----------------------------------------------------------------------------
global dispatch_retry
dispatch_retry:
    push rbx
    push r12
    push r13

    mov rbx, rdi                     ; sink
    mov r12, rsi                      ; record
    xor r13, r13                       ; attempts so far

.try:
    mov rax, [rbx + sink_t.write_fn]
    mov rdi, r12
    mov rsi, 1
    call rax
    cmp rax, 1
    jae .succeeded

    mov rdi, rbx
    call sink_health_note_failure
    mov rdi, rbx
    call dispatch_circuit_breaker_note_failure

    inc r13
    cmp r13, DISPATCH_RETRY_ATTEMPTS
    jl .try

    xor rax, rax
    jmp .done

.succeeded:
    mov rdi, rbx
    call sink_health_mark_ok
    mov rdi, rbx
    call dispatch_circuit_breaker_note_success
    mov rax, 1

.done:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_ULOG_DRAIN_DISPATCH_RETRY_ASM

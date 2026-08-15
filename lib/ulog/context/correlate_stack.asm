; =============================================================================
; Tattva OS — lib/ulog/context/correlate_stack.asm
; =============================================================================
; A nested trace/span stack, one per core (indexed by cpu_id, not folded into
; lib/percpu.inc itself — SPAN_STACK_DEPTH entries is bigger than a single
; named field belongs being, so this is a plain global array following the
; same "no raw offsets" spirit percpu.inc states, just sized for real data).
;
; Cooperative scheduling means exactly one fiber runs per core at a time, so
; "current core's stack top" and "current fiber's trace context" are the same
; thing — this only stops being true across an async handoff, which is
; exactly what correlate_propagate.asm exists to carry across correctly.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_CORRELATE_STACK_ASM
%define LIB_ULOG_CONTEXT_CORRELATE_STACK_ASM

[BITS 64]

%include "lib/percpu.inc"

%define SPAN_STACK_DEPTH  8

struc span_stack_t
    .depth        resd 1
    .reserved     resd 1
    .trace_ids    resq SPAN_STACK_DEPTH
    .span_ids     resq SPAN_STACK_DEPTH
endstruc

section .text

; -----------------------------------------------------------------------------
; correlate_stack_push — enter a new span
; Input:  RDI = trace_id, RSI = span_id
; Output: RAX = 1 ok, 0 if this core's stack is already SPAN_STACK_DEPTH deep
; -----------------------------------------------------------------------------
global correlate_stack_push
correlate_stack_push:
    push rbx
    push rcx

    call correlate_this_cpu_stack             ; RAX = span_stack_t* for this core
    mov rbx, rax

    mov ecx, [rbx + span_stack_t.depth]
    cmp ecx, SPAN_STACK_DEPTH
    jae .full

    mov [rbx + span_stack_t.trace_ids + rcx * 8], rdi
    mov [rbx + span_stack_t.span_ids + rcx * 8], rsi
    inc dword [rbx + span_stack_t.depth]
    mov rax, 1
    jmp .done

.full:
    xor rax, rax

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; correlate_stack_pop — leave the current span
; Input:  none
; Output: none (no-op if already empty)
; -----------------------------------------------------------------------------
global correlate_stack_pop
correlate_stack_pop:
    push rax
    push rbx

    call correlate_this_cpu_stack
    mov rbx, rax
    cmp dword [rbx + span_stack_t.depth], 0
    je .done
    dec dword [rbx + span_stack_t.depth]

.done:
    pop rbx
    pop rax
    ret

; -----------------------------------------------------------------------------
; correlate_get_trace_id / correlate_get_span_id — current top of stack
; Output: RAX = value, or 0 if the stack is empty (no active context)
; -----------------------------------------------------------------------------
global correlate_get_trace_id
correlate_get_trace_id:
    push rbx
    push rcx
    call correlate_this_cpu_stack
    mov rbx, rax
    mov ecx, [rbx + span_stack_t.depth]
    test ecx, ecx
    jz .empty_trace
    dec ecx
    mov rax, [rbx + span_stack_t.trace_ids + rcx * 8]
    jmp .done_trace
.empty_trace:
    xor rax, rax
.done_trace:
    pop rcx
    pop rbx
    ret

global correlate_get_span_id
correlate_get_span_id:
    push rbx
    push rcx
    call correlate_this_cpu_stack
    mov rbx, rax
    mov ecx, [rbx + span_stack_t.depth]
    test ecx, ecx
    jz .empty_span
    dec ecx
    mov rax, [rbx + span_stack_t.span_ids + rcx * 8]
    jmp .done_span
.empty_span:
    xor rax, rax
.done_span:
    pop rcx
    pop rbx
    ret

; ---- correlate_this_cpu_stack: RAX = &ulog_span_stacks[gs:percpu_t.cpu_id] --
correlate_this_cpu_stack:
    push rdx
    mov eax, [gs:percpu_t.cpu_id]
    mov edx, span_stack_t_size
    imul rax, rdx
    add rax, ulog_span_stacks
    pop rdx
    ret

section .bss
alignb 8
global ulog_span_stacks
ulog_span_stacks: resb (span_stack_t_size * PERCPU_MAX_CORES)

%endif ; LIB_ULOG_CONTEXT_CORRELATE_STACK_ASM

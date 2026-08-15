; =============================================================================
; Tattva OS — lib/ulog/context/correlate_propagate.asm
; =============================================================================
; Carries the calling fiber's trace context across a fiber_create() boundary,
; so a request's log trail survives a handoff to a worker fiber instead of
; the new fiber starting with an empty correlate_stack.
;
; A drop-in replacement for a direct fiber_create() call when the caller
; wants the child to inherit context; call fiber_create directly for fibers
; that are deliberately unrelated to any in-flight request (drain_fiber
; itself, for instance).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_CONTEXT_CORRELATE_PROPAGATE_ASM
%define LIB_ULOG_CONTEXT_CORRELATE_PROPAGATE_ASM

[BITS 64]

struc propagate_ctx_t
    .trace_id      resq 1
    .span_id        resq 1
    .real_entry      resq 1
    .real_arg         resq 1
endstruc

section .text

; -----------------------------------------------------------------------------
; correlate_propagate_to_new_fiber — fiber_create, context-preserving
; Input:  RDI = entry_point, RSI = arg, RDX = priority, RCX = restart_policy
; Output: RAX = FCB* (same as fiber_create), 0 on failure
; -----------------------------------------------------------------------------
global correlate_propagate_to_new_fiber
correlate_propagate_to_new_fiber:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                     ; real_entry
    mov r13, rsi                      ; real_arg
    mov r14, rdx                       ; priority
    mov r15, rcx                        ; restart_policy

    mov rdi, propagate_ctx_t_size
    call heap_alloc
    test rax, rax
    jz .fail
    mov rbx, rax                     ; RBX = ctx*

    call correlate_get_trace_id
    mov [rbx + propagate_ctx_t.trace_id], rax
    call correlate_get_span_id
    mov [rbx + propagate_ctx_t.span_id], rax

    mov [rbx + propagate_ctx_t.real_entry], r12
    mov [rbx + propagate_ctx_t.real_arg], r13

    mov rdi, correlate_trampoline
    mov rsi, rbx
    mov rdx, r14
    mov rcx, r15
    call fiber_create
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; correlate_trampoline — the new fiber's actual entry point.
; fiber_create hands the fiber's `arg` back in RDI when it first runs — here
; that arg is the propagate_ctx_t* allocated above.
; -----------------------------------------------------------------------------
correlate_trampoline:
    push rbx
    mov rbx, rdi

    mov rdi, [rbx + propagate_ctx_t.trace_id]
    mov rsi, [rbx + propagate_ctx_t.span_id]
    call correlate_stack_push

    mov rdi, [rbx + propagate_ctx_t.real_arg]
    call [rbx + propagate_ctx_t.real_entry]

    call correlate_stack_pop

    mov rdi, rbx
    call heap_free

    pop rbx
    ret

%endif ; LIB_ULOG_CONTEXT_CORRELATE_PROPAGATE_ASM

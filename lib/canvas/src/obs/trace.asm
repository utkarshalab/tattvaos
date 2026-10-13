; ============================================================================
; Trace — Structured Event Tracing (ring buffer, timestamped)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/trace.inc"

; struct offsets (hoisted above use)
%define Trace_size    56
%define TraceEvent_size    40
%define TRACE_DEFAULT_CAPACITY  4096

section .text

struc Trace
    .server:         resq 1
    .buf:            resq 1
    .capacity:       resq 1
    .head:           resq 1
    .count:          resq 1
    .enabled_mask:   resq 1
    .dropped:        resq 1
endstruc

struc TraceEvent
    .time_ns:       resq 1
    .event_id:      resd 1
    .client_id:     resd 1
    .object:        resd 1
    .opcode:        resw 1
    .flags:         resw 1
    .arg0:          resq 1
    .arg1:          resq 1
endstruc


; ---------------------------------------------------------------------------
; trace_init
; ---------------------------------------------------------------------------
global trace_init
trace_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Trace_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Trace.server], rdi
    mov rdi, [rbx + Trace.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, TRACE_DEFAULT_CAPACITY
    imul rsi, TraceEvent_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rbx + Trace.buf], rax
    mov qword [rbx + Trace.capacity], TRACE_DEFAULT_CAPACITY
    mov qword [rbx + Trace.head], 0
    mov qword [rbx + Trace.count], 0
    mov qword [rbx + Trace.enabled_mask], -1
    mov qword [rbx + Trace.dropped], 0
    mov qword [rdi + Server.trace], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; trace_emit
;   IN: rdi = server*, rsi = event_id, rdx = client_id, rcx = object,
;       r8 = opcode, r9 = arg0, stack arg1
; ---------------------------------------------------------------------------
global trace_emit
trace_emit:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    mov rax, [rbx + Server.trace]
    test rax, rax
    jz .disabled
    mov rbx, rax
    ; category filter: bit (event_id & 63)
    mov rcx, r12
    and rcx, 63
    bt qword [rbx + Trace.enabled_mask], rcx
    jnc .disabled
    mov rax, [rbx + Trace.head]
    mov rdi, [rbx + Trace.buf]
    imul rax, TraceEvent_size
    add rdi, rax
    call tv_time_now_ns
    mov [rdi + TraceEvent.time_ns], rax
    mov [rdi + TraceEvent.event_id], r12d
    mov [rdi + TraceEvent.client_id], r13d
    mov [rdi + TraceEvent.object], r14d
    mov [rdi + TraceEvent.opcode], r15w
    mov word [rdi + TraceEvent.flags], 0
    mov [rdi + TraceEvent.arg0], r9
    mov rax, [rsp + 56]
    mov [rdi + TraceEvent.arg1], rax
    ; advance
    mov rax, [rbx + Trace.head]
    inc rax
    cmp rax, [rbx + Trace.capacity]
    jb .no_wrap
    xor rax, rax
.no_wrap:
    mov [rbx + Trace.head], rax
    mov rax, [rbx + Trace.count]
    cmp rax, [rbx + Trace.capacity]
    jae .full
    inc qword [rbx + Trace.count]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.full:
    inc qword [rbx + Trace.dropped]
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.disabled:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; trace_set_mask
; ---------------------------------------------------------------------------
global trace_set_mask
trace_set_mask:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.trace]
    test rax, rax
    jz .none
    mov [rax + Trace.enabled_mask], rsi
    xor rax, rax
    leave
    ret
.none:
    mov rax, -(ENOMEM)
    leave
    ret

; ---------------------------------------------------------------------------
; trace_clear
; ---------------------------------------------------------------------------
global trace_clear
trace_clear:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.trace]
    test rax, rax
    jz .none
    mov qword [rax + Trace.head], 0
    mov qword [rax + Trace.count], 0
    mov qword [rax + Trace.dropped], 0
    xor rax, rax
    leave
    ret
.none:
    mov rax, -(ENOMEM)
    leave
    ret

section .data
global trace_version
trace_version: dq 0x010000

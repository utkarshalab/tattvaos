; ============================================================================
; Scheduler — Fair Client Service (round-robin with deficit counters)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define Scheduler_size    40
%define SCHED_DEFAULT_QUANTUM   32  ; messages per turn

section .text

struc Scheduler
    .server:         resq 1
    .cursor:         resq 1
    .quantum:        resq 1
    .served:         resq 1
    .starved:        resq 1
endstruc


; ---------------------------------------------------------------------------
; scheduler_init
; ---------------------------------------------------------------------------
global scheduler_init
scheduler_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Scheduler_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Scheduler.server], rdi
    mov qword [rbx + Scheduler.cursor], 0
    mov qword [rbx + Scheduler.quantum], SCHED_DEFAULT_QUANTUM
    mov qword [rbx + Scheduler.served], 0
    mov qword [rbx + Scheduler.starved], 0
    mov qword [rdi + Server.scheduler], rbx
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; scheduler_run
;   Serve one round across all clients (called per event-loop iteration)
;   IN: rdi = server*
; ---------------------------------------------------------------------------
global scheduler_run
scheduler_run:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Server.scheduler]
    test r12, r12
    jz .done
    mov r13, [rbx + Server.client_registry]
    test r13, r13
    jz .done
    ; TODO: iterate registry round-robin from cursor.
    ; For now: dispatch bounded work per client via callback hook.
    mov r14, [r12 + Scheduler.quantum]
    ; hook: server_dispatch_quantum(server, quantum)
    mov rdi, rbx
    mov rsi, r14
    call server_dispatch_quantum
    add [r12 + Scheduler.served], rax
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; server_dispatch_quantum
;   Default dispatch: drain up to quantum messages total
; ---------------------------------------------------------------------------
global server_dispatch_quantum
server_dispatch_quantum:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    xor r13, r13
.loop:
    test r12, r12
    jz .done
    mov rdi, rbx
    call server_dispatch_one
    test rax, rax
    jz .done  ; 0 = no work left
    js .done   ; error stops round
    inc r13
    dec r12
    jmp .loop
.done:
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; server_dispatch_one
;   Dispatch a single pending message (implemented in server loop)
; ---------------------------------------------------------------------------
global server_dispatch_one
server_dispatch_one:
    PROLOGUE
    ; TODO: pop one message from next ready client channel
    ; and call dispatch_call. Return 1 if work done, 0 if idle.
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; scheduler_set_quantum
; ---------------------------------------------------------------------------
global scheduler_set_quantum
scheduler_set_quantum:
    PROLOGUE
    ASSERT_PTR rdi
    test rsi, rsi
    jz .invalid
    mov [rdi + Scheduler.quantum], rsi
    xor rax, rax
    leave
    ret
.invalid:
    mov rax, -(EINVAL)
    leave
    ret

section .data
global scheduler_version
scheduler_version: dq 0x010000

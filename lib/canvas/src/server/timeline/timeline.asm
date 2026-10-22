; ============================================================================
; Timeline — Monotonic Sync Points (64-bit)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_table_init

; struct offsets (hoisted above use)
%define Timeline_handle        0
%define Timeline.handle 0
%define Timeline_generation    4
%define Timeline.generation 4
%define Timeline_current_point 8
%define Timeline.current_point 8
%define Timeline_waiters       16
%define Timeline.waiters 16
%define Timeline_client_id     24
%define Timeline.client_id 24
%define Timeline_size          32

section .text

; ---------------------------------------------------------------------------
; timeline_init
;   Initialize timeline subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global timeline_init
timeline_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.arena], r12
    mov rdi, r12
    mov rsi, 48
    call arena_alloc
    test rax, rax
    jz .init_oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    mov rdx, 1024
    call handle_table_init
    test rax, rax
    js .init_done
    mov [rbx + Server.timeline_table], r13
.init_done:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.init_oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; timeline_create
;   Create timeline
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = timeline_handle, negative error
; ---------------------------------------------------------------------------
global timeline_create
timeline_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate timeline object
    ; struct Timeline { handle, generation, current_point, waiters }
    mov rdi, [rbx + Server.arena]
    mov rsi, 40
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax

    mov dword [r13 + Timeline.handle], 0
    mov dword [r13 + Timeline.generation], 0
    mov qword [r13 + Timeline.current_point], 0
    mov qword [r13 + Timeline.waiters], 0
    mov rax, [r12 + Client.id]
    mov qword [r13 + Timeline.client_id], rax

    ; Create handle
    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r13
    call handle_create
    test rax, rax
    jz .oom
    mov [r13 + Timeline.handle], eax

    mov eax, [r13 + Timeline.handle]
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; timeline_destroy
;   Destroy timeline
; ---------------------------------------------------------------------------
global timeline_destroy
timeline_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found

    mov qword [rax + Timeline.current_point], -1

    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; timeline_signal
;   Signal timeline point
;   IN:  rdi = server*, rsi = timeline_handle, rdx = point
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global timeline_signal
timeline_signal:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; Update current point
    cmp r13, [rbx + Timeline.current_point]
    jbe .done
    mov [rbx + Timeline.current_point], r13

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_found:
    mov rax, -(ENOENT)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; timeline_wait
;   Wait for timeline point
;   IN:  rdi = server*, rsi = timeline_handle, rdx = point, rcx = timeout_ns
;   OUT: rax = 0 OK, ETIMEDOUT, EINTR
; ---------------------------------------------------------------------------
global timeline_wait
timeline_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx

    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r12
    call handle_resolve
    test rax, rax
    jz .not_found
    mov [rsp], rax

    ; Check if already reached
    cmp r13, [rax + Timeline.current_point]
    jbe .reached

    cmp r14, -1
    je .wait
    call tv_time_now_ns
    add rax, r14
    jc .timed_out
    mov [rsp + 8], rax
.wait:
    call tv_wait_yield
    mov rax, [rsp]
    cmp r13, [rax + Timeline.current_point]
    jbe .reached
    cmp r14, -1
    je .wait
    call tv_time_now_ns
    cmp rax, [rsp + 8]
    jb .wait
.timed_out:
    mov rax, -(ETIMEDOUT)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.reached:
    xor rax, rax
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.not_found:
    mov rax, -(ENOENT)
    add rsp, 16
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; timeline_get_point
;   Get current timeline point
;   IN:  rdi = server*, rsi = timeline_handle
;   OUT: rax = current_point, negative error
; ---------------------------------------------------------------------------
global timeline_get_point
timeline_get_point:
    PROLOGUE
    ASSERT_PTR rdi

    mov rdi, [rdi + Server.timeline_table]
    call handle_resolve
    test rax, rax
    jz .not_found

    mov rax, [rax + Timeline.current_point]
    leave
    ret

.not_found:
    mov rax, -(ENOENT)
    leave
    ret

section .data


global timeline_version
timeline_version: dq 0x010000

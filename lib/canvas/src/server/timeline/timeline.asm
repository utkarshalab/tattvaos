; ============================================================================
; Timeline — Monotonic Sync Points (64-bit)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

; ---------------------------------------------------------------------------
; timeline_init
;   Initialize timeline subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global timeline_init
timeline_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.timeline_table], 0
    mov qword [rbx + Server.arena], r12
    xor rax, rax
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
    mov rbx, rax

    mov qword [rbx + Timeline.handle], 0
    mov qword [rbx + Timeline.generation], 0
    mov qword [rbx + Timeline.current_point], 0
    mov qword [rbx + Timeline.waiters], 0
    mov qword [rbx + Timeline.client_id], [r12 + Client.id]

    ; Create handle
    mov rdi, [rdi + Server.timeline_table]
    mov rsi, rbx
    call handle_create
    test rax, rax
    jz .oom
    mov [rbx + Timeline.handle], eax

    mov rax, [rbx + Timeline.handle]
    ret

.oom:
    RETURN_ERROR ENOMEM

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

    ; Wake waiters
    ; TODO

    mov rdi, [rbx + Server.timeline_table]
    mov rsi, r12
    call handle_destroy

    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; timeline_signal
;   Signal timeline point
;   IN:  rdi = server*, rsi = timeline_handle, rdx = point
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global timeline_signal
timeline_signal:
    PROLOGUE_SAVE rbx, r12
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

    ; Wake waiters
    ; TODO

.done:
    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

; ---------------------------------------------------------------------------
; timeline_wait
;   Wait for timeline point
;   IN:  rdi = server*, rsi = timeline_handle, rdx = point, rcx = timeout_ns
;   OUT: rax = 0 OK, ETIMEDOUT, EINTR
; ---------------------------------------------------------------------------
global timeline_wait
timeline_wait:
    PROLOGUE_SAVE rbx, r12, r13, r14
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
    mov rbx, rax

    ; Check if already reached
    cmp r13, [rbx + Timeline.current_point]
    jbe .reached

    ; Wait
    ; TODO: Add to waitset

.reached:
    xor rax, rax
    ret

.not_found:
    RETURN_ERROR ENOENT

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

    mov rax, [rdi + Server.timeline_table]
    call handle_resolve
    test rax, rax
    jz .not_found

    mov rax, [rax + Timeline.current_point]
    ret

.not_found:
    RETURN_ERROR ENOENT

section .data

%define Timeline_handle        0
%define Timeline_generation    4
%define Timeline_current_point 8
%define Timeline_waiters       16
%define Timeline_client_id     24
%define Timeline_size          32

global timeline_version
timeline_version: dq 0x010000
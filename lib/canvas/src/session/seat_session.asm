; ============================================================================
; Seat Session — Per-Seat Session Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc SeatSession {
    .seat:              resq 1
    .user_id:           resq 1
    .active:            resb 1
    .locked:            resb 1
    .lock_surface:      resq 1
    .idle_timer:        resq 1
    .idle_timeout:      resq 1
    .inhibit_count:     resd 1
    .power_inhibit:     resq 1
}
%define SeatSession_size    64

; ---------------------------------------------------------------------------
; seat_session_init
; ---------------------------------------------------------------------------
global seat_session_init
seat_session_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, SeatSession_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + SeatSession.seat], r12
    mov qword [rbx + SeatSession.user_id], 0
    mov byte [rbx + SeatSession.active], 0
    mov byte [rbx + SeatSession.locked], 0
    mov qword [rbx + SeatSession.lock_surface], 0
    mov qword [rbx + SeatSession.idle_timer], 0
    mov qword [rbx + SeatSession.idle_timeout], 300000000000  ; 5 minutes
    mov dword [rbx + SeatSession.inhibit_count], 0
    mov qword [rbx + SeatSession.power_inhibit], 0

    mov qword [r12 + Seat.session_session], rbx

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; seat_session_start
; ---------------------------------------------------------------------------
global seat_session_start
seat_session_start:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov byte [rbx + SeatSession.active], 1
    mov qword [rbx + SeatSession.user_id], r12

    ; Start idle timer
    call seat_session_start_idle_timer

    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_session_start_idle_timer
; ---------------------------------------------------------------------------
seat_session_start_idle_timer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + SeatSession.idle_timer]
    test rax, rax
    jz .create_timer

    ; Timer already exists
    ret

.create_timer:
    mov rdi, [rbx + SeatSession.idle_timeout]
    mov rsi, seat_session_idle_callback
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    jnz .fail
    mov [rbx + SeatSession.idle_timer], rax
    ret

.fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; seat_session_idle_callback
; ---------------------------------------------------------------------------
seat_session_idle_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Lock the session
    call seat_session_lock

    ret

; ---------------------------------------------------------------------------
; seat_session_lock
; ---------------------------------------------------------------------------
global seat_session_lock
seat_session_lock:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp byte [rbx + SeatSession.locked], 1
    je .already_locked

    mov byte [rbx + SeatSession.locked], 1

    ; Create lock surface
    ; TODO: Create lock screen surface

    ; Notify policy
    mov rax, [rbx + SeatSession.seat]
    mov rax, [rax + Seat.shell]
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_session_lock

.done:
    xor rax, rax
    ret

.already_locked:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_session_unlock
; ---------------------------------------------------------------------------
global seat_session_unlock
seat_session_unlock:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    cmp byte [rbx + SeatSession.locked], 0
    je .not_locked

    mov byte [rbx + SeatSession.locked], 0

    ; Destroy lock surface
    ; TODO

    ; Notify policy
    mov rax, [rbx + SeatSession.seat]
    mov rax, [rax + Seat.shell]
    mov rax, [rax + Shell.policy]
    test rax, rax
    jz .done
    mov rdi, rax
    mov rsi, rbx
    call policy_session_unlock

.done:
    xor rax, rax
    ret

.not_locked:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_session_inhibit_idle
; ---------------------------------------------------------------------------
global seat_session_inhibit_idle
seat_session_inhibit_idle:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    inc dword [rbx + SeatSession.inhibit_count]

    ; Cancel idle timer
    mov rax, [rbx + SeatSession.idle_timer]
    test rax, rax
    jz .done
    mov rdi, rax
    call tv_timer_cancel
    mov qword [rbx + SeatSession.idle_timer], 0

.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; seat_session_uninhibit_idle
; ---------------------------------------------------------------------------
global seat_session_uninhibit_idle
seat_session_uninhibit_idle:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    dec dword [rbx + SeatSession.inhibit_count]
    jl .underflow
    test dword [rbx + SeatSession.inhibit_count], 0
    jnz .done

    ; Restart idle timer
    call seat_session_start_idle_timer

.done:
    xor rax, rax
    ret

.underflow:
    mov dword [rbx + SeatSession.inhibit_count], 0
    xor rax, rax
    ret

section .data
global seat_session_version
seat_session_version: dq 0x010000
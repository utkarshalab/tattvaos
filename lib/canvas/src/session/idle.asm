; ============================================================================
; Idle — Idle Detection and Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc IdleManager {
    .server:        resq 1
    .idle_timeout:  resq 1
    .warning_time:  resq 1
    .timer:         resq 1
    .callbacks:     resq 1
    .inhibit_count: resd 1
}
%define IdleManager_size    48

%define IDLE_STATE_ACTIVE    0
%define IDLE_STATE_IDLE      1
%define IDLE_STATE_WARNING   2

%define DEFAULT_IDLE_TIMEOUT    300000000000  ; 5 minutes
%define DEFAULT_WARNING_TIME    30000000000   ; 30 seconds

; ---------------------------------------------------------------------------
; idle_init
; ---------------------------------------------------------------------------
global idle_init
idle_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Server.arena]
    mov rsi, IdleManager_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + IdleManager.server], rdi
    mov qword [rbx + IdleManager.idle_timeout], DEFAULT_IDLE_TIMEOUT
    mov qword [rbx + IdleManager.warning_time], DEFAULT_WARNING_TIME
    mov qword [rbx + IdleManager.timer], 0
    mov qword [rbx + IdleManager.callbacks], 0
    mov dword [rbx + IdleManager.inhibit_count], 0

    mov qword [rdi + Server.idle_manager], rbx

    ; Start idle timer
    call idle_start_timer

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; idle_start_timer
; ---------------------------------------------------------------------------
idle_start_timer:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rax, [rbx + IdleManager.timer]
    test rax, rax
    jnz .done

    mov rdi, [rbx + IdleManager.idle_timeout]
    mov rsi, idle_timeout_callback
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    jnz .fail
    mov [rbx + IdleManager.timer], rax

.done:
    ret

.fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; idle_timeout_callback
; ---------------------------------------------------------------------------
idle_timeout_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Fire idle callbacks
    mov rax, [rbx + IdleManager.callbacks]
    test rax, rax
    jz .done

.callback_loop:
    mov rdi, [rax + 8]  ; callback
    mov rsi, rbx        ; idle manager
    call rdi

    mov rax, [rax + 8]  ; next
    test rax, rax
    jnz .callback_loop

.done:
    ret

; ---------------------------------------------------------------------------
; idle_reset
;   Reset idle timer on user activity
; ---------------------------------------------------------------------------
global idle_reset
idle_reset:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Cancel current timer
    mov rax, [rbx + IdleManager.timer]
    test rax, rax
    jz .no_timer
    mov rdi, rax
    call tv_timer_cancel

.no_timer:
    ; Start new timer
    call idle_start_timer
    ret

; ---------------------------------------------------------------------------
; idle_inhibit
;   Inhibit idle detection
; ---------------------------------------------------------------------------
global idle_inhibit
idle_inhibit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    inc dword [rbx + IdleManager.inhibit_count]

    ; Cancel timer if active
    mov rax, [rbx + IdleManager.timer]
    test rax, rax
    jz .done
    mov rdi, rax
    call tv_timer_cancel
    mov qword [rbx + IdleManager.timer], 0

.done:
    ret

; ---------------------------------------------------------------------------
; idle_uninhibit
; ---------------------------------------------------------------------------
global idle_uninhibit
idle_uninhibit:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    dec dword [rbx + IdleManager.inhibit_count]
    jl .underflow

    test dword [rbx + IdleManager.inhibit_count], 0
    jnz .done

    ; Restart timer
    call idle_start_timer

.done:
    ret

.underflow:
    mov dword [rbx + IdleManager.inhibit_count], 0
    ret

; ---------------------------------------------------------------------------
; idle_set_timeout
; ---------------------------------------------------------------------------
global idle_set_timeout
idle_set_timeout:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov qword [rbx + IdleManager.idle_timeout], rsi

    ; Restart timer with new timeout
    call idle_start_timer
    ret

; ---------------------------------------------------------------------------
; idle_add_callback
; ---------------------------------------------------------------------------
global idle_add_callback
idle_add_callback:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate callback node
    mov rdi, [rbx + Server.arena]
    mov rsi, 16
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rax + 0], rsi    ; callback
    mov qword [rax + 8], [rbx + IdleManager.callbacks]
    mov [rbx + IdleManager.callbacks], rax

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

section .data
global idle_version
idle_version: dq 0x010000
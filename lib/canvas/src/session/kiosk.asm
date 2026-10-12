; ============================================================================
; Kiosk Session — Locked-Down Single-App Session
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc KioskSession {
    .session:         resq 1
    .allowed_app_id:  resq 1
    .restart_on_exit: resb 1
    .allow_exit:      resb 1
    .lock_screen:     resq 1
    .watchdog_timer:  resq 1
}
%define KioskSession_size    56

; ---------------------------------------------------------------------------
; kiosk_init
; ---------------------------------------------------------------------------
global kiosk_init
kiosk_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.kiosk_sessions], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; kiosk_create
;   Create kiosk session for specific app
; ---------------------------------------------------------------------------
global kiosk_create
kiosk_create:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14b, cl
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate kiosk session
    mov rdi, [rbx + Server.arena]
    mov rsi, KioskSession_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    mov qword [rbx + KioskSession.session], r12
    mov qword [rbx + KioskSession.allowed_app_id], r13
    mov byte [rbx + KioskSession.restart_on_exit], r14b
    mov byte [rbx + KioskSession.allow_exit], 0
    mov qword [rbx + KioskSession.lock_screen], 0
    mov qword [rbx + KioskSession.watchdog_timer], 0

    ; Set kiosk policy
    call kiosk_apply_policy

    ; Start watchdog
    call kiosk_start_watchdog

    mov qword [r12 + Session.kiosk_session], rbx

    xor rax, rax
    ret

.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; kiosk_apply_policy
; ---------------------------------------------------------------------------
kiosk_apply_policy:
    PROLOGUE
    ; Set kiosk policy: single fullscreen window, no other windows allowed
    ret

; ---------------------------------------------------------------------------
; kiosk_start_watchdog
; ---------------------------------------------------------------------------
kiosk_start_watchdog:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Start watchdog timer
    mov rdi, 1000000000  ; 1 second
    mov rsi, kiosk_watchdog_callback
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    jnz .fail
    mov [rbx + KioskSession.watchdog_timer], rax
    ret

.fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; kiosk_watchdog_callback
; ---------------------------------------------------------------------------
kiosk_watchdog_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Check if kiosk app is still running
    ; TODO: Check process status

    ; Restart if needed
    ; TODO

    ; Re-arm timer
    mov rdi, 1000000000
    mov rsi, kiosk_watchdog_callback
    mov rdx, rbx
    call tv_timer_register
    ret

; ---------------------------------------------------------------------------
; kiosk_destroy
; ---------------------------------------------------------------------------
global kiosk_destroy
kiosk_destroy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Cancel watchdog
    mov rax, [rbx + KioskSession.watchdog_timer]
    test rax, rax
    jz .done
    mov rdi, rax
    call tv_timer_cancel

.done:
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; kiosk_set_exit_policy
; ---------------------------------------------------------------------------
global kiosk_set_exit_policy
kiosk_set_exit_policy:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov byte [rbx + KioskSession.allow_exit], cl
    xor rax, rax
    ret

section .data
global kiosk_version
kiosk_version: dq 0x010000
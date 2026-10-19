; ============================================================================
; Kiosk Session — Locked-Down Single-App Session
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

section .text

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
    EPILOGUE_RESTORE rbx, r12
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
    mov rsi, KioskSession_SIZE
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
    mov rdi,rbx
    call kiosk_apply_policy
    test rax,rax
    jnz .error

    ; Start watchdog
    mov rdi,rbx
    call kiosk_start_watchdog
    test rax,rax
    jnz .error

    mov qword [r12 + Session.kiosk_session], rbx

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.error:
    EPILOGUE_RESTORE rbx,r12,r13,r14
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; kiosk_apply_policy
; ---------------------------------------------------------------------------
kiosk_apply_policy:
    PROLOGUE_SAVE rbx
    mov rbx,rdi
    ASSERT_PTR rbx
    mov rax,[rbx + KioskSession.session]
    test rax,rax
    jz .invalid
    mov dword [rax + Session.state],1
    mov [rax + Session.kiosk_session],rbx
    xor eax,eax
    EPILOGUE_RESTORE rbx
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; kiosk_start_watchdog
; ---------------------------------------------------------------------------
kiosk_start_watchdog:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    ; Start watchdog timer
    call tv_time_now_ns
    add rax,1000000000
    jc .invalid
    mov rdi,rax
    mov rsi, kiosk_watchdog_callback
    mov rdx, rbx
    call tv_timer_register
    test rax,rax
    js .fail
    mov [rbx + KioskSession.watchdog_timer], rax
    EPILOGUE_RESTORE rbx
    ret

.fail:
    EPILOGUE_RESTORE rbx
    ret
.invalid:
    mov rax,-EINVAL
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; kiosk_watchdog_callback
; ---------------------------------------------------------------------------
kiosk_watchdog_callback:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx

    mov rdi,[rbx + KioskSession.allowed_app_id]
    xor esi,esi
    call tv_task_wait
    cmp rax,-EAGAIN
    je .rearm
    cmp rax,-EINTR
    je .rearm
    test rax,rax
    js .rearm
    cmp byte [rbx + KioskSession.restart_on_exit],0
    je .mark_inactive
    mov rdi,[rbx + KioskSession.allowed_app_id]
    mov rsi,[rbx + KioskSession.session]
    mov rdx,TASK_USER
    call tv_task_spawn
    test rax,rax
    js .mark_inactive
    mov [rbx + KioskSession.allowed_app_id],rax
    jmp .rearm
.mark_inactive:
    mov rax,[rbx + KioskSession.session]
    test rax,rax
    jz .rearm
    mov dword [rax + Session.state],0

    ; Re-arm timer
.rearm:
    call tv_time_now_ns
    add rax,1000000000
    jc .timer_failed
    mov rdi,rax
    mov rsi, kiosk_watchdog_callback
    mov rdx, rbx
    call tv_timer_register
    test rax,rax
    js .timer_failed
    mov [rbx + KioskSession.watchdog_timer],rax
    xor eax,eax
    jmp .out
.timer_failed:
    mov qword [rbx + KioskSession.watchdog_timer],0
.out:
    EPILOGUE_RESTORE rbx
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
    EPILOGUE_RESTORE rbx
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
    EPILOGUE_RESTORE rbx
    ret

section .data
global kiosk_version
kiosk_version: dq 0x010000

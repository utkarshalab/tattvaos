; ============================================================================
; User Session — Per-User Session Management
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define UserSession_size    80
%define SESSION_STATE_INACTIVE    0
%define SESSION_STATE_ACTIVE      1
%define SESSION_STATE_CLOSING     2

section .text

struc UserSession
    .session_id:      resq 1
    .user_id:         resq 1
    .seat:            resq 1
    .start_time:      resq 1
    .last_activity:   resq 1
    .state:           resd 1
    .autostart_apps:  resq 1
    .env_vars:        resq 1
    .cwd:             resq 1
endstruc


; ---------------------------------------------------------------------------
; user_session_init
; ---------------------------------------------------------------------------
global user_session_init
user_session_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.user_sessions], 0
    mov qword [rbx + Server.session_count], 0

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; user_session_create
; ---------------------------------------------------------------------------
global user_session_create
user_session_create:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate session
    mov rdi, [rbx + Server.arena]
    mov rsi, UserSession_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax

    ; Initialize
    mov rax, [rdi + Server.next_session_id]
    inc qword [rdi + Server.next_session_id]
    mov qword [rbx + UserSession.session_id], rax
    mov qword [rbx + UserSession.user_id], r12
    mov qword [rbx + UserSession.seat], r13
    call tv_time_now_ns
    mov qword [rbx + UserSession.start_time], rax
    mov qword [rbx + UserSession.last_activity], rax
    mov dword [rbx + UserSession.state], SESSION_STATE_ACTIVE
    mov qword [rbx + UserSession.autostart_apps], 0
    mov qword [rbx + UserSession.env_vars], 0
    mov qword [rbx + UserSession.cwd], 0

    ; Add to list
    mov rax, [rdi + Server.user_sessions]
    mov [rbx + UserSession.next], rax
    mov [rdi + Server.user_sessions], rbx
    inc qword [rdi + Server.session_count]

    ; Launch autostart apps
    call user_session_launch_autostart

    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; user_session_destroy
; ---------------------------------------------------------------------------
global user_session_destroy
user_session_destroy:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Set state to closing
    mov dword [r12 + UserSession.state], SESSION_STATE_CLOSING

    ; Close all apps in session
    ; TODO

    ; Remove from list
    ; TODO

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; user_session_get
; ---------------------------------------------------------------------------
global user_session_get
user_session_get:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    mov rax, [rbx + Server.user_sessions]
.find_loop:
    test rax, rax
    jz .not_found
    cmp qword [rax + UserSession.session_id], r12
    je .found
    mov rax, [rax + UserSession.next]
    jmp .find_loop

.find_loop:
    mov rax, [rax + UserSession.next]
    test rax, rax
    jnz .find_loop

.not_found:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.found:
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; user_session_launch_autostart
; ---------------------------------------------------------------------------
user_session_launch_autostart:
    PROLOGUE
    ; TODO: Launch autostart applications
    leave
    ret

section .data
global user_session_version
user_session_version: dq 0x010000

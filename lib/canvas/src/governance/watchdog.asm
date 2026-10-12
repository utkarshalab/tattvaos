; ============================================================================
; Watchdog — Unresponsive-Client Detection (ping/pong + deadlines)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc Watchdog {
    .server:         resq 1
    .timeout_ns:     resq 1
    .timer:          resq 1
    .suspects:       resq 1
    .kills:          resq 1
}
%define Watchdog_size    40

%define WATCHDOG_DEFAULT_TIMEOUT  5000000000  ; 5 seconds
%define WATCHDOG_PING_INTERVAL    1000000000  ; 1 second

; ---------------------------------------------------------------------------
; watchdog_init
; ---------------------------------------------------------------------------
global watchdog_init
watchdog_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Watchdog_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + Watchdog.server], rdi
    mov qword [rbx + Watchdog.timeout_ns], WATCHDOG_DEFAULT_TIMEOUT
    mov qword [rbx + Watchdog.timer], 0
    mov qword [rbx + Watchdog.suspects], 0
    mov qword [rbx + Watchdog.kills], 0
    mov qword [rdi + Server.watchdog], rbx
    ; arm periodic sweep
    mov rdi, WATCHDOG_PING_INTERVAL
    mov rsi, watchdog_sweep
    mov rdx, rbx
    call tv_timer_register
    test rax, rax
    jnz .fail
    mov [rbx + Watchdog.timer], rax
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM
.fail:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; watchdog_sweep
;   Periodic check: ping idle clients, kill expired ones
; ---------------------------------------------------------------------------
watchdog_sweep:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Watchdog.server]
    call tv_time_now_ns
    mov r13, rax
    ; iterate client registry
    ; TODO: real iteration; hook provided for event loop
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + Watchdog.timeout_ns]
    call watchdog_check_all
    ; re-arm
    mov rdi, WATCHDOG_PING_INTERVAL
    mov rsi, watchdog_sweep
    mov rdx, rbx
    call tv_timer_register
    ret

; ---------------------------------------------------------------------------
; watchdog_check_all
; ---------------------------------------------------------------------------
global watchdog_check_all
watchdog_check_all:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ; registry iteration is server-specific; expose per-client check
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; watchdog_check_client
;   IN: rdi = server*, rsi = client*
; ---------------------------------------------------------------------------
global watchdog_check_client
watchdog_check_client:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rax, [r12 + Client.last_ping]
    call tv_time_now_ns
    sub rax, [r12 + Client.last_ping]
    mov r13, [rbx + Watchdog.server]
    mov r13, [rbx + Watchdog.timeout_ns]
    cmp rax, r13
    jb .alive
    ; expired: contain + disconnect
    mov rdi, rbx
    mov rsi, r12
    call containment_fault
    mov rax, [rbx + Watchdog.server]
    mov rax, [rax + Server.watchdog]
    inc qword [rax + Watchdog.kills]
    mov rax, 1
    ret
.alive:
    ; send ping
    mov rdi, r12
    call watchdog_ping_client
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; watchdog_ping_client
; ---------------------------------------------------------------------------
watchdog_ping_client:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    call tv_time_now_ns
    mov [rbx + Client.ping_serial], rax
    ; TODO: encode cw_display.ping into rx ring
    ret

; ---------------------------------------------------------------------------
; watchdog_pong
;   Client answered ping
; ---------------------------------------------------------------------------
global watchdog_pong
watchdog_pong:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    call tv_time_now_ns
    mov [rsi + Client.last_ping], rax
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; watchdog_set_timeout
; ---------------------------------------------------------------------------
global watchdog_set_timeout
watchdog_set_timeout:
    PROLOGUE
    ASSERT_PTR rdi
    mov [rdi + Watchdog.timeout_ns], rsi
    xor rax, rax
    ret

section .data
global watchdog_version
watchdog_version: dq 0x010000

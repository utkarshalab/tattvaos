; ============================================================================
; Watchdog — Unresponsive-Client Detection (ping/pong + deadlines)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/canvas_client.inc"
%include "inc/channel.inc"
%include "inc/cwp.inc"

; struct offsets (hoisted above use)
%define Watchdog_SIZE    40
%define WATCHDOG_DEFAULT_TIMEOUT  5000000000  ; 5 seconds
%define WATCHDOG_PING_INTERVAL    1000000000  ; 1 second

section .text

struc Watchdog
    .server:         resq 1
    .timeout_ns:     resq 1
    .timer:          resq 1
    .suspects:       resq 1
    .kills:          resq 1
endstruc


; ---------------------------------------------------------------------------
; watchdog_init
; ---------------------------------------------------------------------------
global watchdog_init
watchdog_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, Watchdog_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov qword [r13 + Watchdog.server], rbx
    mov qword [r13 + Watchdog.timeout_ns], WATCHDOG_DEFAULT_TIMEOUT
    mov qword [r13 + Watchdog.timer], 0
    mov qword [r13 + Watchdog.suspects], 0
    mov qword [r13 + Watchdog.kills], 0
    mov qword [rbx + Server.watchdog], r13
    ; arm periodic sweep
    call tv_time_now_ns
    lea rdi, [rax + WATCHDOG_PING_INTERVAL]
    mov rsi, watchdog_sweep
    mov rdx, r13
    call tv_timer_register
    test rax, rax
    js .fail
    mov [r13 + Watchdog.timer], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

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
    mov rdi, r12
    mov rsi, r13
    mov rdx, [rbx + Watchdog.timeout_ns]
    call watchdog_check_all
    ; re-arm
    call tv_time_now_ns
    lea rdi, [rax + WATCHDOG_PING_INTERVAL]
    mov rsi, watchdog_sweep
    mov rdx, rbx
    call tv_timer_register
    EPILOGUE_RESTORE rbx, r12, r13
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
    mov rax, [rbx + Server.client_registry]
    test rax, rax
    jz .all_done
    mov rdi, rbx
    mov rsi, [rax]                 ; RBTree.root
    call watchdog_walk_tree
.all_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

watchdog_walk_tree:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .walk_done
    mov rsi, [r12]
    call watchdog_walk_tree
    mov rdi, rbx
    mov rsi, [r12 + 40]
    call watchdog_check_client
    mov rdi, rbx
    mov rsi, [r12 + 8]
    call watchdog_walk_tree
.walk_done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
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
    mov r13, [rbx + Server.watchdog]
    test r13, r13
    jz .alive
    cmp qword [r12 + Client.last_ping], 0
    je .alive
    call tv_time_now_ns
    sub rax, [r12 + Client.last_ping]
    cmp rax, [r13 + Watchdog.timeout_ns]
    jb .alive
    ; expired: contain + disconnect
    mov rdi, rbx
    mov rsi, r12
    call containment_fault
    inc qword [r13 + Watchdog.kills]
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.alive:
    ; send ping
    mov rdi, r12
    call watchdog_ping_client
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
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
    sub rsp, 32
    mov dword [rsp + MsgHdr_obj], CWP_OBJ_DISPLAY
    mov word [rsp + MsgHdr_opcode], 2
    mov word [rsp + MsgHdr_flags], CWP_MSG_FLAG_IS_EVENT
    mov dword [rsp + MsgHdr_len], 8
    mov [rsp + 16], rax
    mov rdi, [rbx + Client.rx_ring]
    test rdi, rdi
    jz .ping_disconnected
    mov rsi, rsp
    lea rdx, [rsp + 16]
    call msgbuf_write
    add rsp, 32
    EPILOGUE_RESTORE rbx
    ret
.ping_disconnected:
    add rsp, 32
    mov rax, -(ENOTCONN)
    EPILOGUE_RESTORE rbx
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
    leave
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
    leave
    ret

section .data
global watchdog_version
watchdog_version: dq 0x010000

; ============================================================================
; Client Event Loop — Blocking Dispatch (poll + handlers)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

section .text

; ---------------------------------------------------------------------------
; canvas_event_loop_once
;   IN: rdi=conn, rsi=handler(event*,user), rdx=user
; ---------------------------------------------------------------------------
global canvas_event_loop_once
canvas_event_loop_once:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    sub rsp, ClientEvent_size
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test rax, rax
    jz .none
    mov rdi, rsp
    mov rsi, r12
    mov rdx, r13
    call r12
    mov rax, 1
    add rsp, ClientEvent_size
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.none:
    add rsp, ClientEvent_size
    ; wait briefly for new events
    mov rdi, 1000000
    call ut_time_sleep_ns
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; canvas_event_loop_run
;   Run until handler returns nonzero
; ---------------------------------------------------------------------------
global canvas_event_loop_run
canvas_event_loop_run:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
.loop:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call canvas_event_loop_once
    test rax, rax
    jnz .loop
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

section .data
global canvas_event_loop_version
canvas_event_loop_version: dq 0x010000

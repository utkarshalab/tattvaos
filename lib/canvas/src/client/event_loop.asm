; ============================================================================
; Client Event Loop — Events to a Handler
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern canvas_event_poll

section .text

; ---------------------------------------------------------------------------
; canvas_event_loop_once
;   One event to the handler; with none, the pump turns (or the program
;   yields) once
;   IN:  rdi = conn, rsi = handler(rdi = ClientEvent*, rsi = user) -> rax,
;        rdx = user
;   OUT: rax = the handler's answer, 0 if there was no event
; ---------------------------------------------------------------------------
global canvas_event_loop_once
canvas_event_loop_once:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 152                        ; the event (144); 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    test rax, rax
    jz .idle
    mov rdi, rsp
    mov rsi, r13
    call r12
    jmp .out
.idle:
    mov rax, [rbx + CLIENT_WIRE + ClientWire.pump]
    test rax, rax
    jz .yield
    mov rdi, [rbx + CLIENT_WIRE + ClientWire.pump_arg]
    call rax
    jmp .nothing
.yield:
    call ut_yield
.nothing:
    xor eax, eax
.out:
    add rsp, 152
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; canvas_event_loop_run
;   Events to the handler until it answers nonzero
;   IN:  as canvas_event_loop_once
;   OUT: rax = that answer
; ---------------------------------------------------------------------------
global canvas_event_loop_run
canvas_event_loop_run:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
.loop:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call canvas_event_loop_once
    test rax, rax
    jz .loop
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

section .data
global canvas_event_loop_version
canvas_event_loop_version: dq 0x020000

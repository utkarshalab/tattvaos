; ============================================================================
; Client Events — Poll/Parse Incoming Events
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

section .text

; ---------------------------------------------------------------------------
; canvas_event_poll
;   IN: rdi = conn, rsi = out_event* — OUT: rax = 1 event, 0 none
; ---------------------------------------------------------------------------
global canvas_event_poll
canvas_event_poll:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + ClientConn.rx_ring]
    test rdi, rdi
    jz .none
    mov rsi, r12
    mov rdx, ClientEvent_size
    call ring_pop
    test rax, rax
    jnz .none
    mov rax, 1
    EPILOGUE_RESTORE rbx, r12
    ret
.none:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; canvas_event_type — OUT: rax = event type
; ---------------------------------------------------------------------------
global canvas_event_type
canvas_event_type:
    PROLOGUE
    ASSERT_PTR rdi
    mov eax, [rdi + ClientEvent.type]
    leave
    ret

; ---------------------------------------------------------------------------
; canvas_event_time
; ---------------------------------------------------------------------------
global canvas_event_time
canvas_event_time:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + ClientEvent.time]
    leave
    ret

section .data
global canvas_events_version
canvas_events_version: dq 0x010000

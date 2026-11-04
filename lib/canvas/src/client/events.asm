; ============================================================================
; Client Events — What the Server Sends Unasked
; ============================================================================
; Events held while a call waited come first, in order; then whatever is on
; the channel. A reply nobody waits for is skipped.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%define __EVENTS_INC__
%include "inc/canvas_client.inc"

extern canvas_wire_event
extern canvas_wire_read

section .text

; ---------------------------------------------------------------------------
; canvas_event_poll
;   IN:  rdi = conn, rsi = ClientEvent*
;   OUT: rax = 1 with an event, 0 with none
; ---------------------------------------------------------------------------
global canvas_event_poll
canvas_event_poll:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    lea r8, [rbx + CLIENT_WIRE]
    mov eax, [r8 + ClientWire.head]
    cmp eax, [r8 + ClientWire.tail]
    je .read
    inc dword [r8 + ClientWire.head]
    and eax, CLIENT_EVENTS - 1
    imul eax, eax, ClientEvent_size
    lea rsi, [r8 + ClientWire.events + rax]
    mov rdi, r12
    mov ecx, ClientEvent_size
    rep movsb
    jmp .one
.read:
    mov rdi, rbx
    call canvas_wire_read
    test rax, rax
    js .none
    test word [rbx + CLIENT_WIRE + ClientWire.in_hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .read
    mov rdi, rbx
    mov rsi, r12
    call canvas_wire_event
.one:
    mov eax, 1
    EPILOGUE_RESTORE rbx, r12
.none:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; canvas_event_type
;   IN:  rdi = ClientEvent*
;   OUT: rax = interface << 16 | event (CANVAS_EV_* in inc/canvas_client.inc)
; ---------------------------------------------------------------------------
global canvas_event_type
canvas_event_type:
    mov eax, [rdi + ClientEvent.type]
    ret

; ---------------------------------------------------------------------------
; canvas_event_time
;   IN:  rdi = ClientEvent* of an input event
;   OUT: rax = when the input happened, monotonic ns
; ---------------------------------------------------------------------------
global canvas_event_time
canvas_event_time:
    mov rax, [rdi + ClientEvent.data]
    ret

section .data
global canvas_events_version
canvas_events_version: dq 0x020000

; ============================================================================
; Client Wire — Requests Out, Replies and Events In
; ============================================================================
; canvas_send writes a request and returns. canvas_call writes one and waits
; for its reply, keeping the events that come first for canvas_event_poll; an
; error event while it waits means the server refused a request, so the call
; ends with that error. Nothing come yet: the pump turns, or the program
; yields.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern msgbuf_read
extern msgbuf_write

section .text

; ---------------------------------------------------------------------------
; canvas_send
;   IN:  rdi = conn, esi = interface, edx = request, rcx = payload,
;        r8d = payload bytes
;   OUT: rax = 0, negative error from the channel
; ---------------------------------------------------------------------------
global canvas_send
canvas_send:
    lea rax, [rdi + CLIENT_WIRE + ClientWire.out_hdr]
    mov [rax + MsgHdr.obj], esi
    mov [rax + MsgHdr.opcode], dx
    mov word [rax + MsgHdr.flags], 0
    mov [rax + MsgHdr.len], r8d
    mov rdx, rcx
    mov rsi, rax
    mov rdi, [rdi + ClientConn.tx_ring]
    jmp msgbuf_write

; ---------------------------------------------------------------------------
; canvas_call
;   A request and its reply, which lands in ClientWire.reply
;   IN:  as canvas_send
;   OUT: rax = reply bytes, the negative error the server sent, -ETIMEDOUT
; ---------------------------------------------------------------------------
global canvas_call
canvas_call:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    call canvas_send
    test rax, rax
    js .out
    mov r14d, CLIENT_CALL_TURNS
.wait:
    mov rdi, rbx
    call canvas_wire_read
    test rax, rax
    js .idle
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.in_hdr]
    test word [rcx + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .event
    cmp [rcx + MsgHdr.obj], r12d
    jne .wait                           ; an answer nobody waits for
    movzx edx, word [rcx + MsgHdr.opcode]
    cmp edx, r13d
    jne .wait
    mov r15, rax
    mov rcx, rax
    lea rdi, [rbx + CLIENT_WIRE + ClientWire.reply]
    lea rsi, [rbx + CLIENT_WIRE + ClientWire.in_msg]
    rep movsb
    mov rax, r15
    jmp .out
.event:
    cmp dword [rcx + MsgHdr.obj], CWP_OBJ_DISPLAY
    jne .keep
    cmp word [rcx + MsgHdr.opcode], DISPLAY_EVENT_ERROR
    jne .keep
    mov r15d, [rbx + CLIENT_WIRE + ClientWire.in_msg + 4]   ; error(object, code, ...)
    neg r15
    mov rdi, rbx                        ; the client may want to see it too
    call canvas_wire_queue
    mov rax, r15
    jmp .out
.keep:
    mov rdi, rbx
    call canvas_wire_queue
    jmp .wait
.idle:
    dec r14d
    jz .timeout
    mov rax, [rbx + CLIENT_WIRE + ClientWire.pump]
    test rax, rax
    jz .yield
    mov rdi, [rbx + CLIENT_WIRE + ClientWire.pump_arg]
    call rax
    jmp .wait
.yield:
    call ut_yield
    jmp .wait
.timeout:
    mov rax, -(ETIMEDOUT)
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; canvas_wire_read
;   The next message into ClientWire.in_hdr / in_msg. The capability grant
;   is noted in ClientConn.caps_granted on the way.
;   IN:  rdi = conn
;   OUT: rax = payload bytes, negative if nothing has come
; ---------------------------------------------------------------------------
global canvas_wire_read
canvas_wire_read:
    push rbx
    mov rbx, rdi
    mov rdi, [rbx + ClientConn.rx_ring]
    lea rsi, [rbx + CLIENT_WIRE + ClientWire.in_hdr]
    lea rdx, [rbx + CLIENT_WIRE + ClientWire.in_msg]
    mov ecx, 256
    call msgbuf_read
    test rax, rax
    js .out
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.in_hdr]
    cmp dword [rcx + MsgHdr.obj], CWP_OBJ_DISPLAY
    jne .out
    cmp word [rcx + MsgHdr.opcode], DISPLAY_EVENT_CAPS
    jne .out
    test word [rcx + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jnz .out
    mov rcx, [rbx + CLIENT_WIRE + ClientWire.in_msg]
    mov [rbx + ClientConn.caps_granted], rcx
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; canvas_wire_event
;   The message last read, as a ClientEvent
;   IN:  rdi = conn, rsi = ClientEvent*
; ---------------------------------------------------------------------------
global canvas_wire_event
canvas_wire_event:
    lea r8, [rdi + CLIENT_WIRE]
    mov eax, [r8 + ClientWire.in_hdr + MsgHdr.obj]
    shl eax, 16
    movzx ecx, word [r8 + ClientWire.in_hdr + MsgHdr.opcode]
    or eax, ecx
    mov [rsi + ClientEvent.type], eax
    mov ecx, [r8 + ClientWire.in_hdr + MsgHdr.len]
    cmp ecx, CLIENT_EVENT_DATA
    jbe .sized
    mov ecx, CLIENT_EVENT_DATA
.sized:
    mov [rsi + ClientEvent.length], ecx
    lea rdi, [rsi + ClientEvent.data]
    lea rsi, [r8 + ClientWire.in_msg]
    rep movsb
    ret

; ---------------------------------------------------------------------------
; canvas_wire_queue
;   Hold the message last read for canvas_event_poll; with all CLIENT_EVENTS
;   held it is counted and lost
;   IN:  rdi = conn
; ---------------------------------------------------------------------------
global canvas_wire_queue
canvas_wire_queue:
    lea r8, [rdi + CLIENT_WIRE]
    mov eax, [r8 + ClientWire.tail]
    mov ecx, eax
    sub ecx, [r8 + ClientWire.head]
    cmp ecx, CLIENT_EVENTS
    jae .full
    inc dword [r8 + ClientWire.tail]
    and eax, CLIENT_EVENTS - 1
    imul eax, eax, ClientEvent_size
    lea rsi, [r8 + ClientWire.events + rax]
    jmp canvas_wire_event
.full:
    inc dword [r8 + ClientWire.dropped]
    ret

section .data
global canvas_wire_version
canvas_wire_version: dq 0x010000

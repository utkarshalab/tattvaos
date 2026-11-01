; ============================================================================
; Channel — In-Address-Space Channels (Message Rings + Handle Channel)
; ============================================================================
; A ChannelPair owns one message ring and one handle ring in each direction.
; A Channel is one direction over those rings. A message with handles carries
; MsgFlag_HAS_HANDLES; its handles are a u32 count, then the u32 handles, in
; the handle ring, sent before the message so a reader never sees the message
; without them.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"
%include "inc/ring.inc"

extern arena_alloc
extern ring_init
extern ring_push
extern ring_pop
extern ring_peek
extern ring_free
extern msgbuf_create
extern msgbuf_write
extern msgbuf_read
extern msgbuf_peek
extern msgbuf_available
extern msgbuf_free_space

%define CHANNEL_MSG_BYTES   (128 * 1024)    ; room for the largest message
%define CHANNEL_HANDLES     64

section .text

; ---------------------------------------------------------------------------
; handle_ring_create
;   IN:  rdi = arena, rsi = slots — OUT: rax = Ring*, 0 on failure
; ---------------------------------------------------------------------------
handle_ring_create:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov rsi, Ring_size
    call arena_alloc
    test rax, rax
    jz .out
    mov r13, rax
    mov rdi, r13
    mov rsi, rbx
    mov rdx, r12
    mov ecx, 4                          ; one u32 handle per element
    call ring_init
    test rax, rax
    mov eax, 0
    cmovz rax, r13
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; channel_init
;   Initialize channel pair (server<->client): allocates all four rings
;   IN:  rdi = channel_pair*, rsi = arena, rdx = message ring bytes (0: default),
;        rcx = handle ring slots (0: default)
;   OUT: rax = 0 OK, -ENOMEM
; ---------------------------------------------------------------------------
global channel_init
channel_init:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jnz .msg_ok
    mov r13, CHANNEL_MSG_BYTES
.msg_ok:
    test r14, r14
    jnz .hdl_ok
    mov r14, CHANNEL_HANDLES
.hdl_ok:
    mov qword [rbx + ChannelPair.arena], r12

%macro MSG_RING 1
    mov rdi, r12
    mov rsi, r13
    call msgbuf_create
    test rax, rax
    jz .oom
    mov [rbx + ChannelPair.%1], rax
%endmacro
%macro HANDLE_RING 1
    mov rdi, r12
    mov rsi, r14
    call handle_ring_create
    test rax, rax
    jz .oom
    mov [rbx + ChannelPair.%1], rax
%endmacro
    MSG_RING server_to_client
    MSG_RING client_to_server
    HANDLE_RING server_to_client_handles
    HANDLE_RING client_to_server_handles

    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; channel_send
;   Send message on channel; nothing is written unless all of it fits
;   IN:  rdi = channel*, rsi = msg_hdr*, rdx = payload, rcx = handles (u32[]),
;        r8 = handle_count (sets MsgFlag_HAS_HANDLES in the header)
;   OUT: rax = 0 OK, -ENOSPC if full, -EINVAL if the channel has no handle ring,
;        -EMSGSIZE
; ---------------------------------------------------------------------------
global channel_send
channel_send:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; the count on its way into the ring
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Channel.msg_ring]
    call msgbuf_free_space
    mov ecx, [r12 + MsgHdr.len]
    add rcx, MsgHdr_size
    cmp rax, rcx
    jb .full

    test r15, r15
    jz .message
    mov rdi, [rbx + Channel.handle_ring]
    test rdi, rdi
    jz .invalid
    call ring_free
    lea rcx, [r15 + 1]
    cmp rax, rcx
    jb .full
    or word [r12 + MsgHdr.flags], MsgFlag_HAS_HANDLES

    mov [rsp], r15d
    mov rdi, [rbx + Channel.handle_ring]
    mov rsi, rsp
    call ring_push
    mov [rsp], r15
.handle:
    mov rdi, [rbx + Channel.handle_ring]
    mov rsi, r14
    call ring_push
    add r14, 4
    dec qword [rsp]
    jnz .handle

.message:
    mov rdi, [rbx + Channel.msg_ring]
    mov rsi, r12
    mov rdx, r13
    call msgbuf_write
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.full:
    mov rax, -(ENOSPC)
    jmp .out
.invalid:
    mov rax, -(EINVAL)
    jmp .out

; ---------------------------------------------------------------------------
; channel_recv
;   Receive message from channel; one that does not fit stays queued
;   IN:  rdi = channel*, rsi = msg_hdr*, rdx = payload_buf, rcx = max_payload,
;        r8 = handle_buf (u32[]), r9 = max_handles
;   OUT: rax = payload_len, rdx = handle_count; -EAGAIN if empty, -EMSGSIZE or
;        -ENOSPC if the payload or handles do not fit, -EPROTO if handles are
;        missing
; ---------------------------------------------------------------------------
global channel_recv
channel_recv:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 24
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov [rsp], r9                       ; max handles
    mov qword [rsp + 8], 0              ; handle count
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, [rbx + Channel.msg_ring]
    mov rsi, r12
    call msgbuf_peek
    test rax, rax
    js .out
    mov eax, [r12 + MsgHdr.len]
    cmp rax, r14
    ja .too_large

    test word [r12 + MsgHdr.flags], MsgFlag_HAS_HANDLES
    jz .read
    mov rdi, [rbx + Channel.handle_ring]
    test rdi, rdi
    jz .broken
    lea rsi, [rsp + 8]
    call ring_peek
    test rax, rax
    jnz .broken
    mov rax, [rsp + 8]
    cmp rax, [rsp]
    ja .too_many
    mov rdi, [rbx + Channel.handle_ring]
    lea rsi, [rsp + 16]
    call ring_pop                       ; the count

.read:
    mov rdi, [rbx + Channel.msg_ring]
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    call msgbuf_read
    test rax, rax
    js .out
    mov r14, rax                        ; payload length

    mov r13, [rsp + 8]
.handle:
    test r13, r13
    jz .done
    mov rdi, [rbx + Channel.handle_ring]
    mov rsi, r15
    call ring_pop
    add r15, 4
    dec r13
    jmp .handle
.done:
    mov rax, r14
    mov rdx, [rsp + 8]
.out:
    add rsp, 24
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.too_large:
    mov rax, -(EMSGSIZE)
    jmp .out
.too_many:
    mov rax, -(ENOSPC)
    jmp .out
.broken:
    mov rax, -(EPROTO)
    jmp .out

; ---------------------------------------------------------------------------
; channel_pending
;   IN:  rdi = channel* — OUT: rax = message bytes waiting (0: none)
; ---------------------------------------------------------------------------
global channel_pending
channel_pending:
    ASSERT_PTR rdi
    mov rdi, [rdi + Channel.msg_ring]
    jmp msgbuf_available

section .data

global channel_version
channel_version: dq 0x010100

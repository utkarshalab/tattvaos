; ============================================================================
; Channel — In-Address-Space Channels (Message Rings + Handle Channel)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"
%include "inc/ring.inc"

section .text

; ---------------------------------------------------------------------------
; channel_init
;   Initialize channel pair (server<->client)
;   IN:  rdi = channel_pair*, rsi = arena, rdx = msg_capacity, rcx = handle_capacity
;   OUT: rax = 0 OK
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
    mov r13, 256
.msg_ok:
    test r14, r14
    jnz .hdl_ok
    mov r14, 16
.hdl_ok:

    ; Server->Client message ring
    mov rdi, [rbx + ChannelPair.server_to_client]
    mov rsi, r12
    mov rdx, r13
    mov rcx, 4096          ; max message size
    call ring_init
    test rax, rax
    jnz .fail1

    ; Client->Server message ring
    mov rdi, [rbx + ChannelPair.client_to_server]
    mov rsi, r12
    mov rdx, r13
    mov rcx, 4096
    call ring_init
    test rax, rax
    jnz .fail2

    ; Server->Client handle ring
    mov rdi, [rbx + ChannelPair.server_to_client_handles]
    mov rsi, r12
    mov rdx, r14
    mov rcx, 4             ; handle array (16 handles * 4 bytes = 64 bytes)
    call ring_init
    test rax, rax
    jnz .fail3

    ; Client->Server handle ring
    mov rdi, [rbx + ChannelPair.client_to_server_handles]
    mov rsi, r12
    mov rdx, r14
    mov rcx, 4
    call ring_init
    test rax, rax
    jnz .fail4

    mov qword [rbx + ChannelPair.arena], r12
    xor rax, rax
    ret

.fail1: RETURN_ERROR ENOMEM
.fail2: RETURN_ERROR ENOMEM
.fail3: RETURN_ERROR ENOMEM
.fail4: RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; channel_send
;   Send message on channel
;   IN:  rdi = channel*, rsi = msg_hdr*, rdx = payload, rcx = handles, r8 = handle_count
;   OUT: rax = 0 OK, ENOSPC if full
; ---------------------------------------------------------------------------
global channel_send
channel_send:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Write message
    mov rdi, [rbx + Channel.msg_ring]
    call msgbuf_write
    test rax, rax
    jnz .send_fail

    ; Write handles if any
    test r14, r14
    jz .no_handles
    mov rdi, [rbx + Channel.handle_ring]
    mov rsi, r14
    mov rdx, r8
    call ring_push
    test rax, rax
    jnz .send_fail

.no_handles:
    xor rax, rax
    ret

.send_fail:
    RETURN_ERROR ENOSPC

; ---------------------------------------------------------------------------
; channel_recv
;   Receive message from channel
;   IN:  rdi = channel*, rsi = msg_hdr*, rdx = payload_buf, rcx = max_payload, r8 = handle_buf, r9 = max_handles
;   OUT: rax = payload_len, negative error
; ---------------------------------------------------------------------------
global channel_recv
channel_recv:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Read message
    mov rdi, [rbx + Channel.msg_ring]
    call msgbuf_read
    test rax, rax
    jnz .recv_fail
    mov r13, rax          ; save payload len

    ; Read handles
    mov rdi, [rbx + Channel.handle_ring]
    call ring_peek
    test rax, rax
    jnz .no_handles

    ; Copy handles
    mov rdi, r15
    mov rsi, [rbx + Channel.handle_ring]
    mov rdx, r9
    call ring_pop
    test rax, rax
    jnz .recv_fail

.no_handles:
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.recv_fail:
    RETURN_ERROR EAGAIN

; ---------------------------------------------------------------------------
; channel_pending
;   Check if messages pending
;   IN:  rdi = channel*
;   OUT: rax = message_count
; ---------------------------------------------------------------------------
global channel_pending
channel_pending:
    PROLOGUE
    ASSERT_PTR rdi
    mov rdi, [rdi + Channel.msg_ring]
    call ring_available
    ret

section .data

%define Channel_msg_ring      0
%define Channel_handle_ring   8
%define Channel_client        16
%define Channel_server        24
%define Channel_size          32

%define ChannelPair_server_to_client         0
%define ChannelPair_client_to_server         8
%define ChannelPair_server_to_client_handles 16
%define ChannelPair_client_to_server_handles 24
%define ChannelPair_arena                    32
%define ChannelPair_size                     40

global channel_version
channel_version: dq 0x010000
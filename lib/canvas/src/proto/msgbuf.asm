; ============================================================================
; Message Buffers — Send/Receive Buffers for Channels
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"

; struct offsets (hoisted above use)
%define MsgBuf_buf       0
%define MsgBuf.buf 0
%define MsgBuf_capacity  8
%define MsgBuf.capacity 8
%define MsgBuf_read_pos  16
%define MsgBuf.read_pos 16
%define MsgBuf_write_pos 24
%define MsgBuf.write_pos 24
%define MsgBuf_arena     32
%define MsgBuf.arena 32
%define MsgBuf_size      40

section .text

; ---------------------------------------------------------------------------
; msgbuf_init
;   Initialize message buffer
;   IN:  rdi = msgbuf*, rsi = arena, rdx = capacity
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global msgbuf_init
msgbuf_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    test r13, r13
    jnz .ok
    mov r13, 4096
.ok:
    ; Allocate buffer
    mov rdi, r12
    mov rsi, r13
    call arena_alloc
    test rax, rax
    jz .oom

    mov qword [rbx + MsgBuf.buf], rax
    mov qword [rbx + MsgBuf.capacity], r13
    mov qword [rbx + MsgBuf.read_pos], 0
    mov qword [rbx + MsgBuf.write_pos], 0
    mov qword [rbx + MsgBuf.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; msgbuf_write
;   Write message to buffer
;   IN:  rdi = msgbuf*, rsi = msg_hdr*, rdx = payload_ptr
;   OUT: rax = 0 OK, ENOSPC if full
; ---------------------------------------------------------------------------
global msgbuf_write
msgbuf_write:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r14, [r12 + MsgHdr_len]
    add r14, 12          ; header size

    ; Check space
    mov rax, [rbx + MsgBuf.write_pos]
    mov rcx, [rbx + MsgBuf.read_pos]
    mov rdx, [rbx + MsgBuf.capacity]

    ; Available space calculation
    cmp rax, rcx
    jae .after_read
    ; write_pos >= read_pos
    sub rdx, rax
    add rdx, rcx
    jmp .check_space
.after_read:
    sub rdx, rax
    add rdx, rcx

.check_space:
    ; Need space for message + 1 byte (to distinguish full/empty)
    cmp rdx, r14
    jbe .full

    ; Write header
    mov rdi, [rbx + MsgBuf.buf]
    add rdi, rax
    mov rsi, r12
    mov rcx, 12
    call memcopy

    ; Write payload
    test r13, r13
    jz .no_payload
    mov rdi, [rbx + MsgBuf.buf]
    add rdi, rax
    add rdi, 12
    mov rsi, r13
    mov rcx, [r12 + MsgHdr_len]
    call memcopy

.no_payload:
    ; Update write_pos
    add rax, r14
    cmp rax, [rbx + MsgBuf.capacity]
    jb .no_wrap
    sub rax, [rbx + MsgBuf.capacity]
.no_wrap:
    mov [rbx + MsgBuf.write_pos], rax
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; msgbuf_read
;   Read message from buffer
;   IN:  rdi = msgbuf*, rsi = msg_hdr*, rdx = payload_dst, rcx = max_payload
;   OUT: rax = payload_len, negative error (EAGAIN if empty)
; ---------------------------------------------------------------------------
global msgbuf_read
msgbuf_read:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + MsgBuf.read_pos]
    mov rcx, [rbx + MsgBuf.write_pos]
    cmp rax, rcx
    je .empty

    ; Read header
    mov rdi, [rbx + MsgBuf.buf]
    add rdi, rax
    mov rsi, r12
    mov rcx, 12
    call memcopy

    ; Validate payload length
    mov rdx, [r12 + MsgHdr_len]
    cmp rdx, r14
    ja .payload_too_large

    ; Advance read_pos past header
    add rax, 12
    cmp rax, [rbx + MsgBuf.capacity]
    jb .no_wrap_hdr
    sub rax, [rbx + MsgBuf.capacity]
.no_wrap_hdr:

    ; Read payload
    test rdx, rdx
    jz .no_payload
    cmp rdx, r14
    ja .payload_too_large

    mov rdi, r13
    mov rsi, [rbx + MsgBuf.buf]
    add rsi, rax
    mov rcx, rdx
    call memcopy

    ; Advance read_pos past payload
    add rax, rdx
    cmp rax, [rbx + MsgBuf.capacity]
    jb .no_wrap_payload
    sub rax, [rbx + MsgBuf.capacity]
.no_wrap_payload:

    mov [rbx + MsgBuf.read_pos], rax
    mov rax, rdx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.empty:
    mov rax, -(EAGAIN)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.payload_too_large:
    mov rax, -(EMSGSIZE)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; msgbuf_peek
;   Peek at next message without consuming
; ---------------------------------------------------------------------------
global msgbuf_peek
msgbuf_peek:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rax, [rbx + MsgBuf.read_pos]
    mov rcx, [rbx + MsgBuf.write_pos]
    cmp rax, rcx
    je .empty

    mov rdi, [rbx + MsgBuf.buf]
    add rdi, rax
    mov rsi, r12
    mov rcx, 12
    call memcopy

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

.empty:
    mov rax, -(EAGAIN)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; msgbuf_available
;   Get bytes available to read
; ---------------------------------------------------------------------------
global msgbuf_available
msgbuf_available:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + MsgBuf.write_pos]
    mov rcx, [rdi + MsgBuf.read_pos]
    cmp rax, rcx
    jae .after
    sub rax, rcx
    leave
    ret
.after:
    mov rdx, [rdi + MsgBuf.capacity]
    sub rdx, rcx
    add rax, rdx
    leave
    ret

; ---------------------------------------------------------------------------
; msgbuf_free_space
;   Get free space for writing
; ---------------------------------------------------------------------------
global msgbuf_free_space
msgbuf_free_space:
    PROLOGUE
    ASSERT_PTR rdi
    call msgbuf_available
    mov rcx, [rdi + MsgBuf.capacity]
    sub rcx, rax
    dec rcx          ; keep 1 byte to distinguish full/empty
    mov rax, rcx
    leave
    ret

section .data


global msgbuf_version
msgbuf_version: dq 0x010000

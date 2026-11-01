; ============================================================================
; Message Buffers — Send/Receive Ring Buffers for Channels
; ============================================================================
; A byte ring of whole messages: a 12-byte MsgHdr, then hdr.len payload bytes.
; Either may wrap at the end of the ring. read_pos == write_pos means empty,
; so one byte always stays unused.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"

extern arena_alloc
extern memcopy

struc MsgBuf
    .buf:                     resq 1
    .capacity:                resq 1
    .read_pos:                resq 1
    .write_pos:               resq 1
    .arena:                   resq 1
endstruc

%define MB_INTO_RING    0
%define MB_OUT_OF_RING  1

section .text

; ---------------------------------------------------------------------------
; mb_copy
;   Copy between the ring and outside memory, wrapping at the ring's end
;   IN:  rdi = msgbuf*, rsi = outside pointer, rdx = bytes, rcx = ring position,
;        r8 = MB_INTO_RING / MB_OUT_OF_RING
;   OUT: rax = the position after the copy
; ---------------------------------------------------------------------------
mb_copy:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; the piece; 16-byte aligned at the call
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
.piece:
    test r13, r13
    jz .done
    mov rdx, [rbx + MsgBuf.capacity]
    sub rdx, r14                        ; room before the end
    cmp rdx, r13
    cmova rdx, r13
    mov [rsp], rdx
    mov rdi, [rbx + MsgBuf.buf]
    add rdi, r14
    mov rsi, r12
    test r15, r15
    jz .copy
    xchg rdi, rsi
.copy:
    call memcopy
    mov rdx, [rsp]
    add r12, rdx
    sub r13, rdx
    add r14, rdx
    cmp r14, [rbx + MsgBuf.capacity]
    jb .piece
    xor r14d, r14d
    jmp .piece
.done:
    mov rax, r14
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; msgbuf_init
;   Initialize message buffer
;   IN:  rdi = msgbuf*, rsi = arena, rdx = capacity (0: 4096)
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
;   Write one message
;   IN:  rdi = msgbuf*, rsi = msg_hdr*, rdx = payload (may be 0 when hdr.len is 0)
;   OUT: rax = 0 OK, -ENOSPC if it does not fit, -EMSGSIZE, -EINVAL
; ---------------------------------------------------------------------------
global msgbuf_write
msgbuf_write:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov r14d, [r12 + MsgHdr.len]
    cmp r14, MAX_PAYLOAD_SIZE
    ja .too_large
    test r14, r14
    jz .sized
    test r13, r13
    jz .invalid
.sized:
    mov rdi, rbx
    call msgbuf_free_space
    lea rcx, [r14 + MsgHdr_size]
    cmp rax, rcx
    jb .full

    mov rdi, rbx
    mov rsi, r12
    mov edx, MsgHdr_size
    mov rcx, [rbx + MsgBuf.write_pos]
    mov r8d, MB_INTO_RING
    call mb_copy
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    mov rcx, rax
    mov r8d, MB_INTO_RING
    call mb_copy
    mov [rbx + MsgBuf.write_pos], rax
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.too_large:
    mov rax, -(EMSGSIZE)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; msgbuf_read
;   Read one message
;   IN:  rdi = msgbuf*, rsi = msg_hdr*, rdx = payload_dst, rcx = max_payload
;   OUT: rax = payload_len, -EAGAIN if empty, -EMSGSIZE if it does not fit
;        (the message stays in the ring)
; ---------------------------------------------------------------------------
global msgbuf_read
msgbuf_read:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rcx, [rbx + MsgBuf.read_pos]
    cmp rcx, [rbx + MsgBuf.write_pos]
    je .empty

    mov rdi, rbx
    mov rsi, r12
    mov edx, MsgHdr_size
    mov r8d, MB_OUT_OF_RING
    call mb_copy
    mov r15d, [r12 + MsgHdr.len]
    cmp r15, r14
    ja .too_large

    mov rdi, rbx
    mov rsi, r13
    mov rdx, r15
    mov rcx, rax
    mov r8d, MB_OUT_OF_RING
    call mb_copy
    mov [rbx + MsgBuf.read_pos], rax
    mov rax, r15
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.empty:
    mov rax, -(EAGAIN)
    jmp .out
.too_large:
    mov rax, -(EMSGSIZE)
    jmp .out

; ---------------------------------------------------------------------------
; msgbuf_peek
;   Read the next message's header without consuming it
;   IN:  rdi = msgbuf*, rsi = msg_hdr*
;   OUT: rax = 0 OK, -EAGAIN if empty
; ---------------------------------------------------------------------------
global msgbuf_peek
msgbuf_peek:
    PROLOGUE
    ASSERT_PTR rdi
    ASSERT_PTR rsi
    mov rcx, [rdi + MsgBuf.read_pos]
    cmp rcx, [rdi + MsgBuf.write_pos]
    je .empty
    mov edx, MsgHdr_size
    mov r8d, MB_OUT_OF_RING
    call mb_copy
    xor eax, eax
    leave
    ret
.empty:
    mov rax, -(EAGAIN)
    leave
    ret

; ---------------------------------------------------------------------------
; msgbuf_available
;   Get bytes available to read
; ---------------------------------------------------------------------------
global msgbuf_available
msgbuf_available:
    ASSERT_PTR rdi
    mov rax, [rdi + MsgBuf.write_pos]
    sub rax, [rdi + MsgBuf.read_pos]
    jae .done
    add rax, [rdi + MsgBuf.capacity]    ; the written part wraps
.done:
    ret

; ---------------------------------------------------------------------------
; msgbuf_free_space
;   Get free space for writing
; ---------------------------------------------------------------------------
global msgbuf_free_space
msgbuf_free_space:
    ASSERT_PTR rdi
    sub rsp, 8
    call msgbuf_available
    add rsp, 8
    mov rcx, [rdi + MsgBuf.capacity]
    sub rcx, rax
    dec rcx                             ; one byte tells full from empty
    mov rax, rcx
    ret

section .data

global msgbuf_version
msgbuf_version: dq 0x010100

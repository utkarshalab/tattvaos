; ============================================================================
; Unit Test — Wire Framing and Message Buffers (src/proto/wire.asm, msgbuf.asm)
; ============================================================================
; test_proto_suite -> eax = failed cases (each case returns 0 / 1).
; Wire: the 12-byte header layout, encoding and decoding, size limits,
; validation, handle arrays. Message buffer: order, an empty ring, a full
; ring, messages wrapping at the ring's end, a read that does not fit.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"
%include "inc/cwp.inc"
%include "inc/struct_offsets.inc"

extern channel_init
extern channel_send
extern channel_recv
extern channel_pending
extern ring_free
extern dispatch_init
extern dispatch_register
extern dispatch_call
extern objects_init
extern objects_create
extern objects_resolve
extern objects_ref
extern objects_unref
extern errors_create
extern errors_send
extern errors_from_errno
extern msgbuf_create
extern arena_init
extern memcmp
extern wire_encode_request
extern wire_decode_header
extern wire_validate_message
extern wire_encode_handles
extern wire_decode_handles
extern msgbuf_init
extern msgbuf_write
extern msgbuf_read
extern msgbuf_peek
extern msgbuf_available
extern msgbuf_free_space

%define HEAP_SIZE (4 * 1024 * 1024)
%define RING 64
%define SLOTS 8                         ; handle ring: 7 usable

section .text

global test_proto_suite
global test_proto_main
test_proto_suite:
test_proto_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tw_header_size
    CASE tw_roundtrip
    CASE tw_too_large
    CASE tw_validate
    CASE tw_handles
    CASE tb_order
    CASE tb_empty
    CASE tb_full
    CASE tb_wrap
    CASE tb_too_small
    CASE tc_handles
    CASE tc_plain
    CASE tc_empty
    CASE tc_all_or_nothing
    CASE tc_stays_queued
    CASE td_dispatch
    CASE to_objects
    CASE te_errno
    CASE te_send
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; hdr: object %1, opcode %2, flags %3, %4 payload bytes
%macro HDR 4
    mov dword [rel hdr + MsgHdr.obj], %1
    mov word [rel hdr + MsgHdr.opcode], %2
    mov word [rel hdr + MsgHdr.flags], %3
    mov dword [rel hdr + MsgHdr.len], %4
%endmacro

; a new arena and a RING-byte message buffer
fresh:
    sub rsp, 8
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel mb]
    lea rsi, [rel arena]
    mov edx, RING
    call msgbuf_init
    add rsp, 8
    ret

; msgbuf_write of hdr with the payload at s_data
put:
    sub rsp, 8
    lea rdi, [rel mb]
    lea rsi, [rel hdr]
    lea rdx, [rel s_data]
    call msgbuf_write
    add rsp, 8
    ret

; msgbuf_read into got / out, room rdi -> rax
take:
    sub rsp, 8
    mov rcx, rdi
    lea rdi, [rel mb]
    lea rsi, [rel got]
    lea rdx, [rel out]
    call msgbuf_read
    add rsp, 8
    ret

tw_header_size:
    sub rsp, 8
    mov eax, MsgHdr_size
    cmp eax, 12
    jne .fail
    PASS

tw_roundtrip:
    sub rsp, 8
    HDR 0x11223344, 0x5566, 0x0002, 8
    lea rdi, [rel out]
    lea rsi, [rel hdr]
    lea rdx, [rel s_data]
    call wire_encode_request
    cmp rax, 20
    jne .fail
    cmp dword [rel out], 0x11223344
    jne .fail
    cmp word [rel out + 4], 0x5566
    jne .fail
    cmp word [rel out + 6], 2
    jne .fail
    cmp dword [rel out + 8], 8
    jne .fail
    lea rdi, [rel out + 12]
    lea rsi, [rel s_data]
    mov edx, 8
    call memcmp
    test eax, eax
    jnz .fail
    lea rdi, [rel out]
    lea rsi, [rel got]
    call wire_decode_header
    test rax, rax
    jnz .fail
    cmp dword [rel got + MsgHdr.obj], 0x11223344
    jne .fail
    cmp word [rel got + MsgHdr.opcode], 0x5566
    jne .fail
    cmp dword [rel got + MsgHdr.len], 8
    jne .fail
    PASS

tw_too_large:
    sub rsp, 8
    HDR 1, 1, 0, MAX_PAYLOAD_SIZE + 1
    lea rdi, [rel out]
    lea rsi, [rel hdr]
    lea rdx, [rel s_data]
    call wire_encode_request
    cmp rax, -(EMSGSIZE)
    jne .fail
    mov dword [rel out + 8], MAX_PAYLOAD_SIZE + 1
    lea rdi, [rel out]
    lea rsi, [rel got]
    call wire_decode_header
    cmp rax, -(EMSGSIZE)
    jne .fail
    PASS

tw_validate:
    sub rsp, 8
    lea rdi, [rel out]
    mov esi, 11                         ; shorter than a header
    call wire_validate_message
    cmp rax, -(EINVAL)
    jne .fail
    mov dword [rel out + 8], 8
    lea rdi, [rel out]
    mov esi, 20
    call wire_validate_message
    cmp rax, 12
    jne .fail
    lea rdi, [rel out]
    mov esi, 24                         ; the length disagrees
    call wire_validate_message
    cmp rax, -(EPROTO)
    jne .fail
    mov dword [rel out + 8], 7          ; payload not a multiple of 4
    lea rdi, [rel out]
    mov esi, 19
    call wire_validate_message
    cmp rax, -(EINVAL)
    jne .fail
    PASS

tw_handles:
    sub rsp, 8
    lea rdi, [rel out]
    lea rsi, [rel s_handles]
    mov edx, 3
    call wire_encode_handles
    cmp rax, 16
    jne .fail
    cmp dword [rel out], 3
    jne .fail
    cmp dword [rel out + 12], 0x33
    jne .fail
    lea rdi, [rel out]
    lea rsi, [rel got_h]
    mov edx, 3
    call wire_decode_handles
    cmp rax, 3
    jne .fail
    cmp dword [rel got_h + 8], 0x33
    jne .fail
    lea rdi, [rel out]
    lea rsi, [rel got_h]
    mov edx, 2                          ; no room for three
    call wire_decode_handles
    cmp rax, -(ENOSPC)
    jne .fail
    PASS

tb_order:
    sub rsp, 8
    HDR 1, 10, 0, 4
    call put
    test rax, rax
    jnz .fail
    HDR 2, 20, 0, 0
    call put
    test rax, rax
    jnz .fail
    lea rdi, [rel mb]
    call msgbuf_available
    cmp rax, 28
    jne .fail
    lea rdi, [rel mb]
    lea rsi, [rel got]
    call msgbuf_peek                    ; does not consume
    test rax, rax
    jnz .fail
    cmp dword [rel got + MsgHdr.obj], 1
    jne .fail
    mov edi, 32
    call take
    cmp rax, 4
    jne .fail
    cmp word [rel got + MsgHdr.opcode], 10
    jne .fail
    mov eax, [rel out]
    cmp eax, [rel s_data]
    jne .fail
    mov edi, 32
    call take
    test rax, rax
    jnz .fail
    cmp word [rel got + MsgHdr.opcode], 20
    jne .fail
    PASS

tb_empty:
    sub rsp, 8
    mov edi, 32
    call take
    cmp rax, -(EAGAIN)
    jne .fail
    lea rdi, [rel mb]
    lea rsi, [rel got]
    call msgbuf_peek
    cmp rax, -(EAGAIN)
    jne .fail
    lea rdi, [rel mb]
    call msgbuf_free_space
    cmp rax, RING - 1
    jne .fail
    PASS

tb_full:
    sub rsp, 8
    HDR 1, 1, 0, 40                     ; 52 bytes
    call put
    test rax, rax
    jnz .fail
    HDR 2, 2, 0, 0                      ; 12 more do not fit in the 11 left
    call put
    cmp rax, -(ENOSPC)
    jne .fail
    HDR 3, 3, 0, 8                      ; no payload pointer needed to refuse
    lea rdi, [rel mb]
    lea rsi, [rel hdr]
    xor edx, edx
    call msgbuf_write
    cmp rax, -(EINVAL)
    jne .fail
    PASS

tb_wrap:
    push rbx
    mov ebx, 8                          ; both pass the end many times over
.round:
    HDR 7, 7, 0, 24
    call put
    test rax, rax
    jnz .bad
    mov edi, 32
    call take
    cmp rax, 24
    jne .bad
    cmp dword [rel got + MsgHdr.obj], 7
    jne .bad
    lea rdi, [rel out]
    lea rsi, [rel s_data]
    mov edx, 24
    call memcmp
    test eax, eax
    jnz .bad
    dec ebx
    jnz .round
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

tb_too_small:
    sub rsp, 8
    HDR 1, 1, 0, 16
    call put
    mov edi, 8
    call take
    cmp rax, -(EMSGSIZE)
    jne .fail
    mov edi, 16                         ; it stayed: a larger read gets it
    call take
    cmp rax, 16
    jne .fail
    PASS

; a channel pair; chan is the client-to-server direction
open_channel:
    sub rsp, 8
    lea rdi, [rel pair]
    lea rsi, [rel arena]
    mov edx, 4096
    mov ecx, SLOTS
    call channel_init
    mov rcx, [rel pair + ChannelPair.client_to_server]
    mov [rel chan + Channel.msg_ring], rcx
    mov rcx, [rel pair + ChannelPair.client_to_server_handles]
    mov [rel chan + Channel.handle_ring], rcx
    add rsp, 8
    ret

; channel_send of hdr, the payload at s_data, edi handles from s_handles
send:
    sub rsp, 8
    mov r8d, edi
    lea rdi, [rel chan]
    lea rsi, [rel hdr]
    lea rdx, [rel s_data]
    lea rcx, [rel s_handles]
    call channel_send
    add rsp, 8
    ret

; channel_recv into got / out / got_h, room for edi handles
recv:
    sub rsp, 8
    mov r9d, edi
    lea rdi, [rel chan]
    lea rsi, [rel got]
    lea rdx, [rel out]
    mov ecx, 64
    lea r8, [rel got_h]
    call channel_recv
    add rsp, 8
    ret

tc_handles:
    sub rsp, 8
    call open_channel
    test rax, rax
    jnz .fail
    HDR 9, 4, 0, 8
    mov edi, 3
    call send
    test rax, rax
    jnz .fail
    lea rdi, [rel chan]
    call channel_pending
    cmp rax, 20
    jne .fail
    mov edi, 4
    call recv
    cmp rax, 8
    jne .fail
    cmp rdx, 3
    jne .fail
    test word [rel got + MsgHdr.flags], MsgFlag_HAS_HANDLES
    jz .fail
    cmp dword [rel got_h + 8], 0x33
    jne .fail
    mov eax, [rel out]
    cmp eax, [rel s_data]
    jne .fail
    PASS

tc_plain:
    sub rsp, 8
    call open_channel
    HDR 9, 4, 0, 4
    xor edi, edi
    call send
    test rax, rax
    jnz .fail
    xor edi, edi
    call recv
    cmp rax, 4
    jne .fail
    test rdx, rdx
    jnz .fail
    PASS

tc_empty:
    sub rsp, 8
    call open_channel
    xor edi, edi
    call recv
    cmp rax, -(EAGAIN)
    jne .fail
    lea rdi, [rel chan]
    call channel_pending
    test rax, rax
    jnz .fail
    PASS

tc_all_or_nothing:
    sub rsp, 8
    call open_channel
    HDR 9, 4, 0, 4
    mov edi, SLOTS - 1                  ; these and their count need one too many
    call send
    cmp rax, -(ENOSPC)
    jne .fail
    lea rdi, [rel chan]
    call channel_pending
    test rax, rax
    jnz .fail
    mov rdi, [rel chan + Channel.handle_ring]
    call ring_free
    cmp rax, SLOTS - 1
    jne .fail
    PASS

tc_stays_queued:
    sub rsp, 8
    call open_channel
    HDR 9, 4, 0, 4
    mov edi, 3
    call send
    mov edi, 2                          ; no room for the handles
    call recv
    cmp rax, -(ENOSPC)
    jne .fail
    mov edi, 3
    call recv
    cmp rax, 4
    jne .fail
    cmp rdx, 3
    jne .fail
    PASS

; handlers: return what shows the arguments arrived, or a second value
handler_a:
    lea rax, [rdi + rsi]
    add rax, rdx
    add rax, rcx
    ret
handler_b:
    mov eax, 2
    ret

%macro CALL_OP 2                        ; interface %1, opcode %2
    lea rdi, [rel dispatch]
    mov esi, %1
    mov edx, %2
    mov ecx, 1000
    mov r8d, 200
    mov r9d, 30
    mov r10d, 4
    call dispatch_call
%endmacro
%macro REGISTER 3                       ; interface %1, opcode %2, handler %3
    lea rdi, [rel dispatch]
    mov esi, %1
    mov edx, %2
    lea rcx, [rel %3]
    call dispatch_register
%endmacro

td_dispatch:
    sub rsp, 8
    lea rdi, [rel dispatch]
    lea rsi, [rel arena]
    call dispatch_init
    CALL_OP 3, 5                        ; an empty table
    cmp rax, -(ECWP_OPCODE)
    jne .fail
    REGISTER 3, 5, handler_a
    test rax, rax
    jnz .fail
    CALL_OP 3, 5
    cmp rax, 1234
    jne .fail
    CALL_OP 3, 6
    cmp rax, -(ECWP_OPCODE)
    jne .fail
    CALL_OP 4, 5
    cmp rax, -(ECWP_OPCODE)
    jne .fail
    REGISTER 3, 5, handler_b            ; replaces
    CALL_OP 3, 5
    cmp rax, 2
    jne .fail
    PASS

to_objects:
    push rbx
    lea rdi, [rel objects]
    lea rsi, [rel arena]
    call objects_init
    test rax, rax
    jnz .bad
    lea rdi, [rel objects]
    lea rsi, [rel s_data]
    mov edx, 7                          ; interface
    mov ecx, 1
    call objects_create
    test rax, rax
    jle .bad
    mov rbx, rax
%macro RESOLVE 1
    lea rdi, [rel objects]
    mov rsi, rbx
    mov edx, %1
    call objects_resolve
%endmacro
    RESOLVE 7
    lea rcx, [rel s_data]
    cmp rax, rcx
    jne .bad
    RESOLVE 8                           ; the wrong interface
    test rax, rax
    jnz .bad
    lea rdi, [rel objects]
    mov rsi, rbx
    call objects_ref
    lea rdi, [rel objects]
    mov rsi, rbx
    call objects_unref                  ; 2 -> 1: still there
    RESOLVE 7
    test rax, rax
    jz .bad
    lea rdi, [rel objects]
    mov rsi, rbx
    call objects_unref                  ; 1 -> 0: gone
    test rax, rax
    jnz .bad
    RESOLVE 7
    test rax, rax
    jnz .bad
    lea rdi, [rel objects]
    mov rsi, rbx
    call objects_ref
    cmp rax, -(ENOENT)
    jne .bad
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

%macro ERRNO 2                          ; errno %1 maps to %2
    mov edi, %1
    call errors_from_errno
    cmp rax, %2
    jne .fail
%endmacro

te_errno:
    sub rsp, 8
    ERRNO EINVAL, ECWP_PAYLOAD
    ERRNO EACCES, ECWP_CAP
    ERRNO ENOSPC, ECWP_FULL
    ERRNO ENOSYS, ECWP_OPCODE
    ERRNO ENOENT, ECWP_OBJECT
    ERRNO 9999, ECWP_PARSE
    PASS

te_send:
    push rbx
    lea rdi, [rel arena]
    mov esi, 77
    lea rdx, [rel s_error]
    call errors_create
    mov rbx, rax
    mov qword [rel client + Client.rx_ring], 0
    lea rdi, [rel client]
    mov rsi, rbx
    call errors_send
    cmp rax, -(ENOTCONN)
    jne .bad
    lea rdi, [rel arena]
    mov esi, 1024
    call msgbuf_create
    mov [rel client + Client.rx_ring], rax
    lea rdi, [rel client]
    mov rsi, rbx
    call errors_send
    test rax, rax
    jnz .bad
    mov rdi, [rel client + Client.rx_ring]
    lea rsi, [rel got]
    lea rdx, [rel out]
    mov ecx, 256
    call msgbuf_read
    cmp rax, 24                         ; 12 + 9, rounded up to 4
    jne .bad
    cmp dword [rel got + MsgHdr.obj], CWP_OBJ_DISPLAY
    jne .bad
    test word [rel got + MsgHdr.flags], CWP_MSG_FLAG_IS_EVENT
    jz .bad
    cmp dword [rel out + 4], 77
    jne .bad
    cmp dword [rel out + 8], 9
    jne .bad
    lea rdi, [rel out + 12]
    lea rsi, [rel s_error]
    mov edx, 9
    call memcmp
    test eax, eax
    jnz .bad
    xor eax, eax
    pop rbx
    ret
.bad:
    mov eax, 1
    pop rbx
    ret

section .rodata
s_data:     db "0123456789abcdefghijklmnopqrstuvwxyzABCD"
s_error:    db "bad thing", 0
alignb 4
s_handles:  dd 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77

section .bss
alignb 16
pair:       resb ChannelPair_size
chan:       resb Channel_size
dispatch:   resq 8
objects:    resq 16
client:     resb Client_size
alignb 16
mb:     resq 8
hdr:    resb MsgHdr_size
got:    resb MsgHdr_size
got_h:  resd 4
arena:  resq 8
alignb 16
out:    resb 256
alignb 16
heap:   resb HEAP_SIZE

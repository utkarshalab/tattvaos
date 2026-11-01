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

%define HEAP_SIZE 65536
%define RING 64

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

section .rodata
s_data:     db "0123456789abcdefghijklmnopqrstuvwxyzABCD"
s_handles:  dd 0x11, 0x22, 0x33

section .bss
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

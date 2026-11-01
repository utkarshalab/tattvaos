; ============================================================================
; Unit Test — Client Lifecycle (src/server/client/*)
; ============================================================================
; test_client_suite -> eax = failed cases (each case returns 0 / 1).
; Accepting: ids, the capability grant waiting in the client's ring, a working
; channel in both directions. Teardown: clients leaving in any order leave the
; others intact, unknown ids are refused.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/channel.inc"
%include "inc/caps.inc"
%include "inc/cwp.inc"
%include "inc/struct_offsets.inc"

extern arena_init
extern client_init
extern client_accept
extern client_disconnect
extern client_get
extern msgbuf_read
extern msgbuf_write

%define HEAP_SIZE 65536

section .text

global test_client_suite
global test_client_main
test_client_suite:
test_client_main:
    push rbx
    xor ebx, ebx
%macro CASE 1
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tc_accept
    CASE tc_caps_event
    CASE tc_both_ways
    CASE tc_any_order
    CASE tc_unknown
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

fresh:
    sub rsp, 8
    lea rdi, [rel server]
    xor eax, eax
    mov ecx, Server_size
    rep stosb
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    call client_init
    add rsp, 8
    ret

; client_accept into the pair %1 -> rax
%macro ACCEPT 1
    lea rdi, [rel server]
    lea rsi, [rel %1]
    mov edx, CAP_SHELL
    call client_accept
%endmacro

tc_accept:
    sub rsp, 8
    ACCEPT pair_a
    cmp rax, 1
    jne .fail
    ACCEPT pair_b
    cmp rax, 2
    jne .fail
    lea rdi, [rel server]
    mov esi, 2
    call client_get
    test rax, rax
    jz .fail
    cmp qword [rax + Client.id], 2
    jne .fail
    mov rcx, [rax + Client.rx_ring]
    cmp rcx, [rel pair_b + ChannelPair.server_to_client]
    jne .fail
    mov rcx, [rax + Client.tx_ring]
    cmp rcx, [rel pair_b + ChannelPair.client_to_server]
    jne .fail
    PASS

tc_caps_event:
    sub rsp, 8
    ACCEPT pair_a
    mov rdi, [rel pair_a + ChannelPair.server_to_client]
    lea rsi, [rel hdr]
    lea rdx, [rel out]
    mov ecx, 64
    call msgbuf_read
    cmp rax, 8
    jne .fail
    cmp dword [rel hdr + MsgHdr.obj], CWP_OBJ_DISPLAY
    jne .fail
    mov rax, [rel out]
    mov rcx, CAP_DISPLAY | CAP_BUFFER | CAP_SURFACE | CAP_PRESENT
    and rax, rcx
    cmp rax, rcx                        ; core capabilities always granted
    jne .fail
    PASS

; a message from the client's end, seen by the server through its Client
tc_both_ways:
    sub rsp, 8
    ACCEPT pair_a
    mov dword [rel hdr + MsgHdr.obj], 5
    mov word [rel hdr + MsgHdr.opcode], 6
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], 4
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel s_ping]
    call msgbuf_write
    test rax, rax
    jnz .fail
    lea rdi, [rel server]
    mov esi, 1
    call client_get
    mov rdi, [rax + Client.tx_ring]
    lea rsi, [rel hdr]
    lea rdx, [rel out]
    mov ecx, 64
    call msgbuf_read
    cmp rax, 4
    jne .fail
    mov eax, [rel out]
    cmp eax, [rel s_ping]
    jne .fail
    PASS

tc_any_order:
    sub rsp, 8
    ACCEPT pair_a
    ACCEPT pair_b
    ACCEPT pair_c
    lea rdi, [rel server]
    mov esi, 1                          ; the oldest goes first
    call client_disconnect
    test rax, rax
    jnz .fail
    lea rdi, [rel server]
    mov esi, 1
    call client_get
    test rax, rax
    jnz .fail
    lea rdi, [rel server]               ; the others are untouched
    mov esi, 2
    call client_get
    test rax, rax
    jz .fail
    cmp byte [rax + Client.state], 2    ; CLIENT_ACTIVE
    jne .fail
    mov rdi, [rel pair_c + ChannelPair.server_to_client]
    lea rsi, [rel hdr]
    lea rdx, [rel out]
    mov ecx, 64
    call msgbuf_read
    cmp rax, 8                          ; its grant is still waiting
    jne .fail
    lea rdi, [rel server]
    mov esi, 3
    call client_disconnect
    test rax, rax
    jnz .fail
    lea rdi, [rel server]
    mov esi, 2
    call client_disconnect
    test rax, rax
    jnz .fail
    PASS

tc_unknown:
    sub rsp, 8
    ACCEPT pair_a
    lea rdi, [rel server]
    mov esi, 99
    call client_disconnect
    cmp rax, -(ESRCH)
    jne .fail
    lea rdi, [rel server]
    mov esi, 1
    call client_disconnect
    lea rdi, [rel server]
    mov esi, 1                          ; twice
    call client_disconnect
    cmp rax, -(ESRCH)
    jne .fail
    PASS

section .rodata
s_ping:     db "ping"

section .bss
alignb 16
server:     resb Server_size
arena:      resb Arena_size
pair_a:     resb ChannelPair_size
pair_b:     resb ChannelPair_size
pair_c:     resb ChannelPair_size
hdr:        resb MsgHdr_size
alignb 8
out:        resb 64
alignb 16
heap:       resb HEAP_SIZE

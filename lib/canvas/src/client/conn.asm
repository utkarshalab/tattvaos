; ============================================================================
; Client Conn — Connecting to the Server
; ============================================================================
; canvas_connect_pair takes a channel pair the server has made for this
; client, as client_accept does inside canvasd. canvas_connect, for other
; programs, needs the kernel to hand out the server's channels (KRN-03) and
; fails until it does.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_init

section .text

; ---------------------------------------------------------------------------
; canvas_connect
;   IN:  rdi = capabilities wanted
;   OUT: rax = conn*, 0: no way to reach the server yet
; ---------------------------------------------------------------------------
global canvas_connect
canvas_connect:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; canvas_connect_pair
;   A connection over a channel pair the server made
;   IN:  rdi = ChannelPair* (the client's end), rsi = pump function, called
;        with rdi = rdx while a call waits (0: yield instead), rdx = its
;        argument
;   OUT: rax = conn*, 0 if there was no memory
; ---------------------------------------------------------------------------
global canvas_connect_pair
canvas_connect_pair:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    mov edi, CLIENT_REGION_SIZE
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .fail
    mov r14, rax
    mov rdi, rax                        ; everything before the heap starts clear
    xor eax, eax
    mov ecx, CLIENT_HEAP_OFFSET
    rep stosb
    mov [r14 + ClientConn.region_handle], r8

    mov [r14 + ClientConn.server_chan], rbx
    mov rax, [rbx + ChannelPair.client_to_server]
    mov [r14 + ClientConn.tx_ring], rax
    mov rax, [rbx + ChannelPair.server_to_client]
    mov [r14 + ClientConn.rx_ring], rax
    mov dword [r14 + ClientConn.next_obj], 1
    mov [r14 + CLIENT_WIRE + ClientWire.pump], r12
    mov [r14 + CLIENT_WIRE + ClientWire.pump_arg], r13

    lea rdi, [r14 + CLIENT_WIRE + ClientWire.arena]
    mov [r14 + ClientConn.arena], rdi
    lea rsi, [r14 + CLIENT_HEAP_OFFSET]
    mov edx, CLIENT_REGION_SIZE - CLIENT_HEAP_OFFSET
    call arena_init
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
.fail:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; canvas_disconnect
;   Free the connection. The server learns of it from its side of the
;   channel, not from a request.
;   IN:  rdi = conn
; ---------------------------------------------------------------------------
global canvas_disconnect
canvas_disconnect:
    ASSERT_PTR rdi
    mov rdi, [rdi + ClientConn.region_handle]
    jmp ut_mem_free

; ---------------------------------------------------------------------------
; canvas_get_caps
;   IN:  rdi = conn
;   OUT: rax = the capabilities the server granted, 0 before its grant came
; ---------------------------------------------------------------------------
global canvas_get_caps
canvas_get_caps:
    ASSERT_PTR rdi
    mov rax, [rdi + ClientConn.caps_granted]
    ret

section .data
global canvas_conn_version
canvas_conn_version: dq 0x020000

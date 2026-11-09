; ============================================================================
; Client Conn — Connecting to the Server
; ============================================================================
; canvas_connect_pair takes a channel pair the server has made for this
; client, as client_accept does inside canvasd. canvas_connect, for other
; programs, finds the server by the name it published ("canvas",
; ut_service_lookup), hands its entry a pair of its own, and waits until the
; server's loop has accepted it (server/client/service.asm).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/canvas_client.inc"

extern arena_init

section .text

%define CONNECT_TURNS   100000          ; waits for the server, at most

; ---------------------------------------------------------------------------
; canvas_connect
;   Connect to canvasd from another program, yielding while it accepts
;   IN:  rdi = capabilities wanted
;   OUT: rax = conn*, 0: no server, refused, or no memory
; ---------------------------------------------------------------------------
global canvas_connect
canvas_connect:
    xor esi, esi
    xor edx, edx
    jmp canvas_connect_with

; ---------------------------------------------------------------------------
; canvas_connect_with
;   As canvas_connect, turning a pump while it waits (as canvas_connect_pair
;   takes one; 0: yield)
;   IN:  rdi = capabilities wanted, rsi = pump, rdx = its argument
;   OUT: rax = conn*, 0: no server, refused, or no memory
; ---------------------------------------------------------------------------
global canvas_connect_with
canvas_connect_with:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov r12, rdi
    mov r13, rsi
    mov r14, rdx
    lea rdi, [rel canvas_service_name]  ; the server, by its name
    call ut_service_lookup
    test rax, rax
    jle .none
    mov r15, rax                        ; its entry
    mov [rsp], rdx                      ; and cookie
    mov edi, 4096                       ; a pair of the client's own
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .none
    mov rbx, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, ChannelPair_size
    rep stosb
    mov [rbx + ChannelPair.region], r8
    mov rdi, [rsp]                      ; asked for
    mov rsi, rbx
    mov rdx, r12
    call r15
    test rax, rax
    js .refused
    mov r12d, CONNECT_TURNS
.wait:
    mov rax, [rbx + ChannelPair.state]  ; the server's loop sets it
    test rax, rax
    jnz .answered
    dec r12d
    jz .refused
    test r13, r13
    jz .yield
    mov rdi, r14
    call r13
    jmp .wait
.yield:
    call ut_yield
    jmp .wait
.answered:
    js .refused
    mov rdi, rbx
    mov rsi, r13
    mov rdx, r14
    call canvas_connect_pair
    test rax, rax
    jz .refused
    jmp .out
.refused:
    mov rdi, [rbx + ChannelPair.region]
    call ut_mem_free
.none:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

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
    push rbx
    mov rbx, [rdi + ClientConn.server_chan] ; a pair canvas_connect made goes
    mov rdi, [rdi + ClientConn.region_handle]
    call ut_mem_free
    test rbx, rbx
    jz .out
    mov rdi, [rbx + ChannelPair.region]
    test rdi, rdi
    jz .out
    call ut_mem_free
.out:
    pop rbx
    ret

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

section .rodata
canvas_service_name:    db "canvas", 0  ; as server/client/service.asm publishes

section .data
global canvas_conn_version
canvas_conn_version: dq 0x020000

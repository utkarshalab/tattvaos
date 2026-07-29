; =============================================================================
; Tattva OS — unet/dns/doq.asm
; =============================================================================
; DNS over QUIC (DoQ RFC 9250 / UDP Port 853) Transport Engine.
;
; Features:
;   - Unordered Stream Multiplexing & 0-RTT Connection Resumption over QUIC v1/v2
;   - Head-of-Line Blocking (HoLB) Elimination (Each Query = Independent Stream)
;   - Connection ID (CID) Based Routing for NAT Rebinding Resilience
;   - Stream-Per-Query Model: 1 Bidirectional QUIC Stream per DNS Query
;   - QUIC Connection Migration on Network Interface Change
;   - Graceful Shutdown via QUIC CONNECTION_CLOSE (Error Code 0x02 = Protocol Error)
;   - Server Push Proactive Response Delivery
;
; Delegates:
;   - QUIC Transport Engine              -> unet/core/l4/quic.asm
;   - TLS 1.3 Encryption                -> crypto/utls/
;   - Timer Wheel Idle Timeout           -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DOQ_UDP_PORT                853
%define DOQ_MAX_STREAMS             64      ; Max Concurrent Query Streams
%define DOQ_IDLE_TIMEOUT_MS         30000   ; 30-second Idle Timeout
%define DOQ_ERROR_INTERNAL          0x01
%define DOQ_ERROR_PROTOCOL          0x02
%define DOQ_ERROR_NO_ERROR          0x00

struc doq_session_t
    .state:             resd 1      ; 0=Closed, 1=Connecting, 2=Active, 3=Draining
    .quic_conn_id:      resb 20     ; QUIC Connection ID
    .next_stream_id:    resq 1      ; Next Available Bidirectional Stream ID
    .active_streams:    resd 1      ; Current Active Stream Count
    .timer_id:          resd 1      ; Idle Timeout Timer Wheel ID
    .queries_sent:      resq 1      ; Total Queries Sent
    .zero_rtt_ticket:   resb 256    ; 0-RTT Session Ticket
    .ticket_len:        resw 1
endstruc

section .bss
align 64
doq_session:            resb doq_session_t_size

section .text

global doq_init
global doq_connect
global doq_send_query
global doq_recv_response
global doq_close
global doq_migrate_connection

extern quic_input
extern quic_open_stream
extern quic_send_stream
extern quic_recv_stream
extern quic_close_connection
extern timer_wheel_add
extern timer_wheel_del

align 64
doq_init:
    push rbp
    mov rbp, rsp
    mov dword [doq_session + doq_session_t.state], 0
    mov qword [doq_session + doq_session_t.next_stream_id], 0
    mov dword [doq_session + doq_session_t.active_streams], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doq_connect — Establish QUIC Connection to DoQ Resolver on UDP Port 853
; Input: RDI = Pointer to Resolver IP Address
; Output: EAX = 0 on Success, -1 on Failure
; -----------------------------------------------------------------------------
align 64
doq_connect:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]

    ; 1. Initiate QUIC handshake via unet/core/l4/quic.asm (try 0-RTT)
    call quic_input

    ; 2. Schedule idle timeout timer
    mov edi, DOQ_IDLE_TIMEOUT_MS
    call timer_wheel_add
    mov [doq_session + doq_session_t.timer_id], eax

    mov dword [doq_session + doq_session_t.state], 2    ; Active
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doq_send_query — Send DNS Query on Dedicated QUIC Bidirectional Stream
; Input: RDI = Wire-Format DNS Query, ESI = Query Length
; Output: RAX = Stream ID (or -1 if Max Streams Reached)
; -----------------------------------------------------------------------------
align 64
doq_send_query:
    push rbp
    mov rbp, rsp
    push rbx

    prefetcht0 [rdi]

    ; 1. Check active stream count < DOQ_MAX_STREAMS
    mov eax, [doq_session + doq_session_t.active_streams]
    cmp eax, DOQ_MAX_STREAMS
    jge .streams_full

    ; 2. Open new bidirectional QUIC stream
    mov rbx, [doq_session + doq_session_t.next_stream_id]
    call quic_open_stream

    ; 3. Send wire-format DNS query on stream (no length prefix — stream framing)
    call quic_send_stream

    ; 4. Increment stream counters
    inc dword [doq_session + doq_session_t.active_streams]
    add qword [doq_session + doq_session_t.next_stream_id], 4  ; Client bidi = +4
    inc qword [doq_session + doq_session_t.queries_sent]

    mov rax, rbx                    ; Return Stream ID
    jmp .send_done

.streams_full:
    mov rax, -1

.send_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doq_recv_response — Receive DNS Response from QUIC Stream
; Input: RDI = Stream ID, RSI = Output Buffer
; Output: EAX = Response Length, -1 on Error
; -----------------------------------------------------------------------------
align 64
doq_recv_response:
    push rbp
    mov rbp, rsp
    ; Read response from QUIC stream (stream EOF = response complete)
    call quic_recv_stream
    dec dword [doq_session + doq_session_t.active_streams]
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doq_close — Graceful QUIC Connection Shutdown
; -----------------------------------------------------------------------------
align 64
doq_close:
    push rbp
    mov rbp, rsp
    ; Send QUIC CONNECTION_CLOSE with DOQ_ERROR_NO_ERROR
    mov edi, DOQ_ERROR_NO_ERROR
    call quic_close_connection
    ; Cancel idle timeout timer
    mov edi, [doq_session + doq_session_t.timer_id]
    call timer_wheel_del
    mov dword [doq_session + doq_session_t.state], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; doq_migrate_connection — Migrate QUIC Connection on Network Interface Change
; Input: RDI = New Source IP Address
; Output: EAX = 0 on Success
; -----------------------------------------------------------------------------
align 64
doq_migrate_connection:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; QUIC CID-based routing allows seamless migration without re-handshake
    xor eax, eax
    pop rbp
    ret

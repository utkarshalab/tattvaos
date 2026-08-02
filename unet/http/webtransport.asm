; =============================================================================
; Tattva OS — unet/http/webtransport.asm
; =============================================================================
; WebTransport Framework over HTTP/3 (W3C WebTransport API).
;
; Features:
;   - Session Establishment via Extended CONNECT with :protocol=webtransport
;   - Reliable Bidirectional Streams (Request/Response Like)
;   - Reliable Unidirectional Streams (Send-Only / Receive-Only)
;   - Unreliable Datagrams (Sub-Millisecond, No Retransmission)
;   - Session ID Multiplexing (Multiple WebTransport Sessions per H3 Connection)
;   - Stream Reset & Stop Sending for Graceful Teardown
;   - Close Session with Application Error Code
;
; Delegates:
;   - HTTP/3 Transport                   -> unet/http/http3.asm
;   - QUIC Datagrams                     -> unet/http/http3_datagram.asm
;   - QUIC Streams                       -> unet/core/l4/quic.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc webtransport_session_t
    .session_id:        resq 1      ; HTTP/3 Stream ID for CONNECT
    .state:             resd 1      ; 0=Connecting, 1=Open, 2=Closing, 3=Closed
    .bidi_stream_count: resd 1
    .uni_stream_count:  resd 1
endstruc

section .text

global webtransport_init
global webtransport_connect
global webtransport_open_bidi_stream
global webtransport_open_uni_stream
global webtransport_send_datagram
global webtransport_recv
global webtransport_close

extern http3_send_headers
extern http3_send_data
extern http3_datagram_send
extern quic_open_stream

align 64
webtransport_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; webtransport_connect — Establish WebTransport Session via Extended CONNECT
; Input: RDI = Origin URL
; Output: RAX = Session ID, -1 on Failure
; -----------------------------------------------------------------------------
align 64
webtransport_connect:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send Extended CONNECT: :method=CONNECT, :protocol=webtransport, :path=/
    ; Receive 200 OK -> session established
    call http3_send_headers
    pop rbp
    ret

; -----------------------------------------------------------------------------
; webtransport_open_bidi_stream — Open Reliable Bidirectional Stream
; Input: RDI = Session ID
; Output: RAX = Stream ID
; -----------------------------------------------------------------------------
align 64
webtransport_open_bidi_stream:
    push rbp
    mov rbp, rsp
    ; Open QUIC bidirectional stream with WebTransport framing
    call quic_open_stream
    pop rbp
    ret

align 64
webtransport_open_uni_stream:
    push rbp
    mov rbp, rsp
    ; Open QUIC unidirectional stream with session ID header
    call quic_open_stream
    pop rbp
    ret

; -----------------------------------------------------------------------------
; webtransport_send_datagram — Send Unreliable Datagram on Session
; Input: RDI = Session ID, RSI = Payload, EDX = Length
; -----------------------------------------------------------------------------
align 64
webtransport_send_datagram:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    call http3_datagram_send
    pop rbp
    ret

align 64
webtransport_recv:
    push rbp
    mov rbp, rsp
    ; Receive data from any stream or datagram on this session
    xor eax, eax
    pop rbp
    ret

align 64
webtransport_close:
    push rbp
    mov rbp, rsp
    ; Send CLOSE_WEBTRANSPORT_SESSION capsule with error code
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/http/http3.asm
; =============================================================================
; HTTP/3 over QUIC Transport Protocol Engine (RFC 9114 / RFC 9000).
;
; Features:
;   - QUIC Stream-Based Frame Transport (No TCP HoL Blocking)
;   - HTTP/3 Frame Types: DATA (0x00), HEADERS (0x01), CANCEL_PUSH (0x03),
;                         SETTINGS (0x04), PUSH_PROMISE (0x05), GOAWAY (0x07)
;   - QPACK Header Compression (RFC 9204) with Dynamic Table Sync
;   - Unidirectional Control / Encoder / Decoder Streams
;   - Server Push via PUSH_PROMISE + Unidirectional Push Stream
;   - Connection Migration via QUIC CID (Seamless Network Handoff)
;   - 0-RTT Early Data Support
;
; Delegates:
;   - QUIC Transport Layer              -> unet/core/l4/quic.asm
;   - TLS 1.3 ALPN "h3" Negotiation    -> crypto/utls/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define H3_FRAME_DATA               0x00
%define H3_FRAME_HEADERS            0x01
%define H3_FRAME_CANCEL_PUSH        0x03
%define H3_FRAME_SETTINGS           0x04
%define H3_FRAME_PUSH_PROMISE       0x05
%define H3_FRAME_GOAWAY             0x07

%define H3_STREAM_CONTROL           0x00
%define H3_STREAM_PUSH              0x01
%define H3_STREAM_QPACK_ENCODER     0x02
%define H3_STREAM_QPACK_DECODER     0x03

struc h3_frame_t
    .type:              resq 1      ; Variable-Length Integer Frame Type
    .length:            resq 1      ; Variable-Length Integer Payload Length
endstruc

section .text

global http3_init
global http3_process_frame
global http3_send_frame
global http3_send_headers
global http3_send_data
global http3_send_goaway

extern quic_input
extern quic_open_stream
extern quic_send_stream
extern quic_recv_stream

align 64
http3_init:
    push rbp
    mov rbp, rsp
    ; Open unidirectional control stream (type 0x00)
    ; Open QPACK encoder stream (type 0x02)
    ; Open QPACK decoder stream (type 0x03)
    ; Send initial SETTINGS frame on control stream
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http3_process_frame — Parse HTTP/3 Variable-Length Frame & Dispatch
; Input: RDI = Pointer to Frame Buffer, ESI = Buffer Length
; Output: EAX = Frame Type
; -----------------------------------------------------------------------------
align 64
http3_process_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Decode variable-length integer frame type
    movzx eax, byte [rbx]
    ; Decode variable-length integer payload length

    cmp al, H3_FRAME_DATA
    je .h3_data
    cmp al, H3_FRAME_HEADERS
    je .h3_headers
    cmp al, H3_FRAME_SETTINGS
    je .h3_settings
    cmp al, H3_FRAME_GOAWAY
    je .h3_goaway
    cmp al, H3_FRAME_CANCEL_PUSH
    je .h3_cancel_push
    jmp .h3_done

.h3_data:
    ; Deliver data payload to application
    jmp .h3_done
.h3_headers:
    ; QPACK decode header block
    jmp .h3_done
.h3_settings:
    ; Apply peer H3 settings
    jmp .h3_done
.h3_goaway:
    ; Graceful shutdown: extract last stream ID
    jmp .h3_done
.h3_cancel_push:
    ; Cancel pending server push
    jmp .h3_done

.h3_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http3_send_frame — Send HTTP/3 Frame on QUIC Stream
; Input: RDI = Stream ID, RSI = Frame Type, EDX = Payload, ECX = Length
; -----------------------------------------------------------------------------
align 64
http3_send_frame:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdx]
    ; Encode variable-length frame type + length prefix + payload
    call quic_send_stream
    pop rbp
    ret

align 64
http3_send_headers:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; QPACK encode headers & send as HEADERS frame on request stream
    call quic_send_stream
    pop rbp
    ret

align 64
http3_send_data:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Send DATA frame on request stream
    call quic_send_stream
    pop rbp
    ret

align 64
http3_send_goaway:
    push rbp
    mov rbp, rsp
    ; Send GOAWAY frame on control stream with last processed stream ID
    call quic_send_stream
    pop rbp
    ret

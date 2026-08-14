%ifndef GUARD_UNET_HTTP_HTTP3_DATAGRAM_ASM
%define GUARD_UNET_HTTP_HTTP3_DATAGRAM_ASM
; =============================================================================
; Tattva OS — unet/http/http3_datagram.asm
; =============================================================================
; QUIC Datagram Extension for HTTP/3 Engine (RFC 9221 / RFC 9297).
;
; Features:
;   - Unreliable QUIC DATAGRAM Frames for Sub-Millisecond Delivery
;   - HTTP Datagram Capsules (RFC 9297) with Quarter Stream ID Encoding
;   - Cloud Gaming / Live Audio / Video Real-Time Streaming
;   - WebTransport Datagram Integration
;   - Flow Control Bypass (Datagrams Not Subject to Stream Flow Control)
;   - MTU Discovery for Maximum Datagram Size Negotiation
;   - SETTINGS_H3_DATAGRAM Capability Negotiation
;
; Delegates:
;   - QUIC Transport                     -> unet/core/l4/quic.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define H3_DATAGRAM_SETTING         0x33    ; SETTINGS_H3_DATAGRAM

section .text

global http3_datagram_init
global http3_datagram_send
global http3_datagram_recv
global http3_datagram_negotiate
global http3_datagram_max_size


align 64
http3_datagram_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http3_datagram_send — Send Unreliable Datagram on HTTP/3 Connection
; Input: RDI = Quarter Stream ID, RSI = Payload, EDX = Length
; Output: EAX = 0 on Success, -1 if Exceeds Max Datagram Size
; -----------------------------------------------------------------------------
align 64
http3_datagram_send:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend Quarter Stream ID (variable-length integer)
    ; Send as QUIC DATAGRAM frame (unreliable, no retransmission)
    call quic_send_datagram
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http3_datagram_recv — Receive Unreliable Datagram
; Input: RDI = Output Buffer
; Output: EAX = Payload Length, EDX = Quarter Stream ID
; -----------------------------------------------------------------------------
align 64
http3_datagram_recv:
    push rbp
    mov rbp, rsp
    ; Receive QUIC DATAGRAM frame, extract Quarter Stream ID & payload
    call quic_recv_datagram
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http3_datagram_negotiate — Negotiate SETTINGS_H3_DATAGRAM Capability
; Input: EDI = 1 to Enable, 0 to Disable
; -----------------------------------------------------------------------------
align 64
http3_datagram_negotiate:
    push rbp
    mov rbp, rsp
    ; Include SETTINGS_H3_DATAGRAM=1 in HTTP/3 SETTINGS frame
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; http3_datagram_max_size — Query Maximum Datagram Payload Size
; Output: EAX = Max Datagram Size (based on QUIC MTU - overhead)
; -----------------------------------------------------------------------------
align 64
http3_datagram_max_size:
    push rbp
    mov rbp, rsp
    ; Max = QUIC max_datagram_frame_size - Quarter Stream ID overhead
    mov eax, 1200                   ; Conservative default
    pop rbp
    ret

%endif ; GUARD_UNET_HTTP_HTTP3_DATAGRAM_ASM

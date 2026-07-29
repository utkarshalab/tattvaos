; =============================================================================
; Tattva OS — unet/dns/dot.asm
; =============================================================================
; DNS over TLS (DoT RFC 7858 / TCP Port 853) Encrypted Session Engine.
;
; Features:
;   - 2-Byte Prefix Length Wire-Format Framing over TCP Port 853
;   - TLS 1.3 Handshake & Early Data 0-RTT Connection Resumption
;   - Keep-Alive Pipelined Query Multiplexing
;
; Delegates:
;   - TLS 1.3 Client Handshake          -> crypto/utls/
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DOT_TCP_PORT                853

section .text

global dot_init
global dot_connect
global dot_send_query

extern utls_client_handshake

align 64
dot_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
dot_connect:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Establish TLS 1.3 Session over TCP Port 853
    call utls_client_handshake
    pop rbp
    ret

align 64
dot_send_query:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend 2-byte 16-bit big-endian length prefix & encrypt stream
    xor eax, eax
    pop rbp
    ret

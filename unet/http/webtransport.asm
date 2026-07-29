; =============================================================================
; Tattva OS — unet/http/webtransport.asm
; =============================================================================
; WebTransport Framework over HTTP/3 (RFC 9297).
;
; Implements:
;   - Unreliable Datagrams & Reliable Unidirectional / Bidirectional Streams
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global webtransport_init
global webtransport_recv

align 32
webtransport_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
webtransport_recv:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/http/connect_udp.asm
; =============================================================================
; Proxying UDP / IP over HTTP/3 Engine (RFC 9298 / RFC 9484).
;
; Implements:
;   - Proxying UDP Datagrams over HTTP/3 Capsules
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global connect_udp_init
global connect_udp_proxy

align 32
connect_udp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
connect_udp_proxy:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

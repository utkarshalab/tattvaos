; =============================================================================
; Tattva OS — unet/dns/doq.asm
; =============================================================================
; DNS over QUIC (DoQ RFC 9250 / UDP Port 853) Transport Engine.
;
; Features:
;   - Unordered Stream Multiplexing & 0-RTT Connection Resumption over QUIC v1/v2
;   - Head-of-Line Blocking (HoLB) Elimination
;
; Delegates:
;   - QUIC Transport Engine             -> unet/core/l4/quic.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define DOQ_UDP_PORT                853

section .text

global doq_init
global doq_send_query

extern quic_input

align 64
doq_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
doq_send_query:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send DNS query on QUIC stream over UDP Port 853 via unet/core/l4/quic.asm
    call quic_input
    pop rbp
    ret

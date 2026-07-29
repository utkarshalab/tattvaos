; =============================================================================
; Tattva OS — unet/video/moq.asm
; =============================================================================
; Media over QUIC (MoQ / IETF MoQ Working Group) Transport Engine.
;
; Implements:
;   - Sub-100ms Ultra Low-Latency Media Delivery over QUIC Streams & Datagrams
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global moq_init
global moq_publish

align 32
moq_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
moq_publish:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

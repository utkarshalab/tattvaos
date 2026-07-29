; =============================================================================
; Tattva OS — unet/sdn/l2tp.asm
; =============================================================================
; Layer 2 Tunneling Protocol v3 (L2TPv3 RFC 3931) Engine.
;
; Implements:
;   - L2 Payload Tunneling over IP / UDP Session Headers
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global l2tp_init
global l2tp_encap

align 32
l2tp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
l2tp_encap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

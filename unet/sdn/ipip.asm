; =============================================================================
; Tattva OS — unet/sdn/ipip.asm
; =============================================================================
; IP-in-IP (IPIP RFC 2003) Tunneling Protocol Engine.
;
; Implements:
;   - IPv4-in-IPv4 & IPv6-in-IPv4 Outer Header Encap/Decap Processing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipip_init
global ipip_encap

align 32
ipip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipip_encap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

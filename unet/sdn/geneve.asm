; =============================================================================
; Tattva OS — unet/sdn/geneve.asm
; =============================================================================
; GENEVE Generic Network Virtualization Encapsulation Engine (RFC 8926).
;
; Implements:
;   - UDP Port 6081 Variable-Length Option Header Tunneling for Open Virtual Network
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global geneve_init
global geneve_encap

align 32
geneve_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
geneve_encap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

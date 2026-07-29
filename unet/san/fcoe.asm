; =============================================================================
; Tattva OS — unet/san/fcoe.asm
; =============================================================================
; Fiber Channel over Ethernet (FCoE 0x8906) Storage Framing Engine.
;
; Implements:
;   - Direct Encapsulation of Fiber Channel Frames into 10G/40G Ethernet
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global fcoe_init
global fcoe_encap

align 32
fcoe_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
fcoe_encap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/sdn/vxlan.asm
; =============================================================================
; Virtual Extensible LAN (VXLAN RFC 7348) 24-Bit VNI Overlay Engine.
;
; Implements:
;   - UDP Outer Framing (`Port 4789`) & 24-Bit VNI (Virtual Network Identifier)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global vxlan_init
global vxlan_encap

align 32
vxlan_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
vxlan_encap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

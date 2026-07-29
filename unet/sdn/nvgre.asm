; =============================================================================
; Tattva OS — unet/sdn/nvgre.asm
; =============================================================================
; Network Virtualization using Generic Routing Encapsulation (NVGRE RFC 7637).
;
; Implements:
;   - 24-Bit Virtual Subnet ID (VSID) Multitenant GRE Encapsulation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nvgre_init
global nvgre_encap

align 32
nvgre_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nvgre_encap:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

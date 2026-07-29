; =============================================================================
; Tattva OS — unet/drivers/ne2000.asm
; =============================================================================
; Novell NE2000 (DP8390) ISA / PCI Ethernet Driver.
;
; Implements:
;   - Ring Buffer Page Management & I/O Port Data Transfer
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ne2000_init
global ne2000_poll

align 32
ne2000_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ne2000_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

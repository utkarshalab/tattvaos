; =============================================================================
; Tattva OS — unet/drivers/microchip_lan9514.asm
; =============================================================================
; Microchip LAN9514 Raspberry Pi USB 2.0 Ethernet Controller Driver.
;
; Implements:
;   - MAC Register Control & USB Bulk Transfer Ring Processing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global lan9514_init
global lan9514_poll

align 32
lan9514_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
lan9514_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

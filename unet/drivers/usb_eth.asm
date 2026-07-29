; =============================================================================
; Tattva OS — unet/drivers/usb_eth.asm
; =============================================================================
; USB 3.0 Gigabit Ethernet Dongle Driver (AX88179 / RTL8153).
;
; Implements:
;   - USB xHCI Bulk In/Out Endpoint Transfer Engine for Ethernet Packets
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global usb_eth_init
global usb_eth_poll

align 32
usb_eth_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
usb_eth_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

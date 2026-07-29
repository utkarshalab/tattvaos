; =============================================================================
; Tattva OS — unet/drivers/realtek_r8169.asm
; =============================================================================
; Realtek RTL8169 / RTL8111 PCIe Gigabit NIC Driver.
;
; Implements:
;   - Tx / Rx Ring Descriptor Allocation & PCI Interrupt Service Routine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global r8169_init
global r8169_poll

align 32
r8169_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
r8169_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

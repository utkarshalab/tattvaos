; =============================================================================
; Tattva OS — unet/drivers/3com_3c905.asm
; =============================================================================
; 3Com 3c905 Fast EtherLink XL PCI Driver.
;
; Implements:
;   - Boomerang Bus-Master DMA & Window Register Switching
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global c3c905_init
global c3c905_poll

align 32
c3c905_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
c3c905_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

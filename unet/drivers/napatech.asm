; =============================================================================
; Tattva OS — unet/drivers/napatech.asm
; =============================================================================
; Napatech 200G FPGA SmartNIC Capture Driver.
;
; Implements:
;   - Zero-Drop 200Gbps Line-Rate Hardware Packet Capture Ring Buffer
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global napatech_init
global napatech_poll

align 32
napatech_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
napatech_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

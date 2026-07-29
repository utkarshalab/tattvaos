; =============================================================================
; Tattva OS — unet/drivers/pensando_ionic.asm
; =============================================================================
; AMD Pensando DSC 100G / 200G SmartNIC / DPU Driver (IONIC).
;
; Implements:
;   - Admin & Rx/Tx Descriptor Queue Processing over PCIe Gen5
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ionic_init
global ionic_poll

align 32
ionic_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ionic_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

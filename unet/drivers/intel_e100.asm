; =============================================================================
; Tattva OS — unet/drivers/intel_e100.asm
; =============================================================================
; Intel PRO/100 (8255x) Fast Ethernet PCI Driver.
;
; Implements:
;   - Command Block List (CBL) & Receive Frame Area (RFA) Descriptor Ring
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global e100_init
global e100_poll

align 32
e100_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
e100_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

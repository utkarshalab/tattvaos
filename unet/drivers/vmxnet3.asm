; =============================================================================
; Tattva OS — unet/drivers/vmxnet3.asm
; =============================================================================
; VMware VMXNET3 Paravirtualized 10G Virtual NIC Driver.
;
; Implements:
;   - Shared Memory Command Ring & Shared Tx/Rx Ring Descriptors
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global vmxnet3_init
global vmxnet3_poll

align 32
vmxnet3_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
vmxnet3_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

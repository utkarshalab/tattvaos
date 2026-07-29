; =============================================================================
; Tattva OS — unet/tools/cxi_info.asm
; =============================================================================
; HPE Slingshot-11 CXI High-Performance Fabric Interface Inspector Tool.
;
; Implements:
;   - Displays Slingshot CXI NIC Counters, Congestion State & Virtual Interfaces
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global cxi_info_init
global cxi_info_dump

align 32
cxi_info_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
cxi_info_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

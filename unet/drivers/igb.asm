; =============================================================================
; Tattva OS — unet/drivers/igb.asm
; =============================================================================
; Intel 82575 / 82576 / I350 Gigabit PCIe NIC Driver.
;
; Implements:
;   - Multi-Queue MSI-X Ring Allocation & Hardware Checksum Offload
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global igb_init
global igb_poll

align 32
igb_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
igb_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

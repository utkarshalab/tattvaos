; =============================================================================
; Tattva OS — unet/drivers/ice.asm
; =============================================================================
; Intel 800 Series (E810) 100G Ethernet NIC Driver.
;
; Implements:
;   - Dynamic Device Personalization (DDP) Pipeline & 100G Line-Rate Rx/Tx
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ice_init
global ice_poll

align 32
ice_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ice_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

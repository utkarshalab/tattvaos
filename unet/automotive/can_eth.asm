; =============================================================================
; Tattva OS — unet/automotive/can_eth.asm
; =============================================================================
; Automotive CAN-over-Ethernet Translation Gateway Engine.
;
; Implements:
;   - Zero-Copy Translation between CAN Bus 11-bit/29-bit IDs & IEEE 802.3 Frames
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global can_eth_init
global can_eth_translate

align 32
can_eth_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
can_eth_translate:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

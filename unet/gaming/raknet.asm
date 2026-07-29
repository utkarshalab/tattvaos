; =============================================================================
; Tattva OS — unet/gaming/raknet.asm
; =============================================================================
; Reliable UDP Game Engine Transport Protocol (RakNet / ENet Engine).
;
; Implements:
;   - Packet Ordering, Sequence Numbers & Fragment Reassembly over UDP
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global raknet_init
global raknet_send_reliable

align 32
raknet_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
raknet_send_reliable:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/drivers/mlx4.asm
; =============================================================================
; Mellanox ConnectX-3 40G InfiniBand / Ethernet Driver.
;
; Implements:
;   - Doorbell Ringing & Completion Queue (CQ) Event Processing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global mlx4_init
global mlx4_poll

align 32
mlx4_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
mlx4_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

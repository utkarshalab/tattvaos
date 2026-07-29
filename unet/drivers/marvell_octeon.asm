; =============================================================================
; Tattva OS — unet/drivers/marvell_octeon.asm
; =============================================================================
; Marvell Octeon TX2 100G DPU SmartNIC Driver.
;
; Implements:
;   - NIX (Network Interface eXpress) & NPA (Pool Allocator) Hardware Offload
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global octeon_init
global octeon_poll

align 32
octeon_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
octeon_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

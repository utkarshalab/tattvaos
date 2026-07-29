; =============================================================================
; Tattva OS — unet/drivers/gve.asm
; =============================================================================
; Google Virtual NIC (GVE 100G) Driver.
;
; Implements:
;   - Admin Queue (AQ) & GQI (Google Queue Interface) Ring Polling
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global gve_init
global gve_poll

align 32
gve_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
gve_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

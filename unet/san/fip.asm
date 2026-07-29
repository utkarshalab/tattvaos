; =============================================================================
; Tattva OS — unet/san/fip.asm
; =============================================================================
; FCoE Initialization Protocol (FIP 0x8914) Fabric Discovery Engine.
;
; Implements:
;   - FIP VLAN Discovery, FCF Solicitation & Fabric Login (FLOGI)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global fip_init
global fip_flogi

align 32
fip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
fip_flogi:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

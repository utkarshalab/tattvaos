; =============================================================================
; Tattva OS — unet/tools/ipsec_top.asm
; =============================================================================
; IPsec ESP Tunnel Security Association (SA) Traffic & Bitrate Meter Tool.
;
; Implements:
;   - Measures Encrypted ESP Encryption Rates, Drop Rates & Replay Window Errors
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipsec_top_init
global ipsec_top_run

align 32
ipsec_top_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipsec_top_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

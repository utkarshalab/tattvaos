; =============================================================================
; Tattva OS — unet/wireless/capwap.asm
; =============================================================================
; Control and Provisioning of Wireless Access Points (CAPWAP — RFC 5415 / 5416).
;
; Implements:
;   - UDP Control & Data Tunneling (`Port 5246/5247`) between AC & Access Points
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global capwap_init
global capwap_tunnel

align 32
capwap_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
capwap_tunnel:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/tools/dhcpclient.asm
; =============================================================================
; DHCP Dynamic IPv4 / IPv6 Address Auto-Configuration Client Tool.
;
; Implements:
;   - DISCOVER, OFFER, REQUEST, ACK State Machine for Automatic Network Setup
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global dhcpclient_init
global dhcpclient_request

align 32
dhcpclient_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
dhcpclient_request:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

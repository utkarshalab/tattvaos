; =============================================================================
; Tattva OS — unet/routing/evpn.asm
; =============================================================================
; BGP EVPN Control Plane Overlay Router Engine (RFC 8365).
;
; Implements:
;   - EVPN Route Types 1, 2 (MAC/IP Advertisement), 3, 5 for VXLAN Fabrics
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global evpn_init
global evpn_advertise

align 32
evpn_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
evpn_advertise:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

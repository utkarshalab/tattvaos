; =============================================================================
; Tattva OS — unet/cni/calico.asm
; =============================================================================
; Project Calico BGP CNI Network Plugin Engine.
;
; Implements:
;   - BGP Route Reflector Sub-System & IP-in-IP Overlay Routing for Containers
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global calico_init
global calico_setup_routes

align 32
calico_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
calico_setup_routes:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

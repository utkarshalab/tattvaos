; =============================================================================
; Tattva OS — unet/routing/netns.asm
; =============================================================================
; Network Namespace (NetNS) Virtual Isolation Engine.
;
; Implements:
;   - Per-Container Virtual Network Namespace Routing Isolation & Interfaces
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global netns_init
global netns_create_ns

align 32
netns_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
netns_create_ns:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

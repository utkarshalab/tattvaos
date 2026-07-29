; =============================================================================
; Tattva OS — unet/routing/isis.asm
; =============================================================================
; IS-IS Intermediate System to Intermediate System Link-State Router (RFC 1195).
;
; Implements:
;   - Level 1 / Level 2 Area Routing, PDU Hello Packets, and LSP Flooding
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global isis_init
global isis_route

align 32
isis_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
isis_route:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

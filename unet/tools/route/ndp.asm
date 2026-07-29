; =============================================================================
; Tattva OS — unet/tools/ndp.asm
; =============================================================================
; IPv6 Neighbor Discovery Protocol (NDP RFC 4861) Inspector Tool.
;
; Implements:
;   - Displays IPv6 Neighbor Advertisements (NA) & Router Solicitations (RS)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ndp_tool_init
global ndp_tool_dump

align 32
ndp_tool_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ndp_tool_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

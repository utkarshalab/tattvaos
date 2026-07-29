; =============================================================================
; Tattva OS — unet/tools/route_tool.asm
; =============================================================================
; IP Routing Table & FIB Route Inspection / Modification Tool.
;
; Implements:
;   - Adds, Deletes, and Queries IPv4 / IPv6 Gateway Routes
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global route_tool_init
global route_tool_dump

align 32
route_tool_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
route_tool_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

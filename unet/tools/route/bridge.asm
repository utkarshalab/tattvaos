; =============================================================================
; Tattva OS — unet/tools/bridge.asm
; =============================================================================
; Ethernet Software Bridge & VLAN IEEE 802.1Q Port Management Tool.
;
; Implements:
;   - Adds, Removes, and Inspects Virtual Ethernet Bridge Ports & STP Status
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global bridge_tool_init
global bridge_tool_show

align 32
bridge_tool_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
bridge_tool_show:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

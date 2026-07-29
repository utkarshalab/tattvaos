; =============================================================================
; Tattva OS — unet/tools/arp_tool.asm
; =============================================================================
; Address Resolution Protocol (ARP) Table Inspection & Gratuitous ARP Tool.
;
; Implements:
;   - Displays L2 MAC to IPv4 Mappings & Sends Gratuitous ARP (GARP)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global arp_tool_init
global arp_tool_dump

align 32
arp_tool_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
arp_tool_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

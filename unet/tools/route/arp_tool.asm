%ifndef GUARD_UNET_TOOLS_ROUTE_ARP_TOOL_ASM
%define GUARD_UNET_TOOLS_ROUTE_ARP_TOOL_ASM
; =============================================================================
; Tattva OS — unet/tools/route/arp_tool.asm
; =============================================================================
; Command-Line ARP Cache Inspector & Gratuitous ARP Tool (`arp`).
;
; Features:
;   - Dynamic ARP Cache Display (IP -> MAC Mapping, State REACHABLE/STALE)
;   - Static Entry Addition & Deletion
;   - Gratuitous ARP Broadcast Sender (`arping`)
;
; Delegates:
;   - ARP Protocol                      -> unet/core/l2/arp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global arp_tool_main


align 64
arp_tool_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Broadcast Gratuitous ARP & display local ARP cache table
    call arp_send_gratuitous
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_ROUTE_ARP_TOOL_ASM

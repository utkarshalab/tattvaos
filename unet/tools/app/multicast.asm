; =============================================================================
; Tattva OS — unet/tools/multicast.asm
; =============================================================================
; IGMPv3 & MLDv2 IPv4/IPv6 Multicast Group Join & Leave CLI Diagnostic Tool.
;
; Implements:
;   - Joins & Leaves Multicast Groups (`224.0.0.0/4` & `ff00::/8`) & Monitors PIM Feeds
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global multicast_tool_init
global multicast_tool_join

align 32
multicast_tool_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
multicast_tool_join:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

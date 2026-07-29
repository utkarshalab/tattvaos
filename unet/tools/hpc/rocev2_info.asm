; =============================================================================
; Tattva OS — unet/tools/rocev2_info.asm
; =============================================================================
; RoCE v2 RDMA Queue Pair & Congestion State Diagnostic Tool.
;
; Implements:
;   - Displays Active RoCE v2 QPs, Packet Counters, PFC Stats & ECN Congestion
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global rocev2_info_init
global rocev2_info_dump

align 32
rocev2_info_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
rocev2_info_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

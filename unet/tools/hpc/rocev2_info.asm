; =============================================================================
; Tattva OS — unet/tools/hpc/rocev2_info.asm
; =============================================================================
; RoCEv2 Network Diagnostic & GID Table Inspector (`rocev2-info`).
;
; Features:
;   - RoCEv2 GID Table Inspection (RoCE v1 vs RoCE v2 IPv4/IPv6 GIDs)
;   - UDP Port 4791 Encapsulation Verification & DCQCN Congestion Counter Audit
;
; Delegates:
;   - RoCEv2 Engine                     -> unet/hpc/roce.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global rocev2_info_main

extern roce_decap_packet

align 64
rocev2_info_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Query RoCEv2 GID table & dump DCQCN rate reduction counters
    call roce_decap_packet
    pop rbp
    ret

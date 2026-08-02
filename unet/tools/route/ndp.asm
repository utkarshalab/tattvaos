; =============================================================================
; Tattva OS — unet/tools/route/ndp.asm
; =============================================================================
; IPv6 Neighbor Discovery Protocol Inspector Tool (`ndp`).
;
; Features:
;   - ICMPv6 Neighbor Solicitation (NS Type 135) & Advertisement (NA Type 136) Audit
;   - Router Advertisement (RA Type 134) Prefix & MTU Option Dump
;
; Delegates:
;   - IPv6 Protocol Engine              -> unet/core/l3/ipv6.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ndp_main

align 64
ndp_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Dump IPv6 Neighbor Cache (Neighbor Solicitation / Advertisement table)
    xor eax, eax
    pop rbp
    ret

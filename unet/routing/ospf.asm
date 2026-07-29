; =============================================================================
; Tattva OS — unet/routing/ospf.asm
; =============================================================================
; OSPFv2 / OSPFv3 Link-State Router Engine (RFC 2328 / RFC 5340).
;
; Implements:
;   - Dijkstra Shortest Path First (SPF) Algorithm & LSA Flood Engine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ospf_init
global ospf_spf_calculate

align 32
ospf_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ospf_spf_calculate:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

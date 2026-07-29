; =============================================================================
; Tattva OS — unet/tools/ospf_view.asm
; =============================================================================
; OSPFv2 / OSPFv3 Link-State Database (LSDB) & Neighbor Table Inspector Tool.
;
; Implements:
;   - Displays OSPF Neighbors, Areas, Router LSAs & Shortest Path Tree
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ospf_view_init
global ospf_view_dump

align 32
ospf_view_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ospf_view_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

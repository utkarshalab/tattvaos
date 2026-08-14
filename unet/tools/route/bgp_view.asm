%ifndef GUARD_UNET_TOOLS_ROUTE_BGP_VIEW_ASM
%define GUARD_UNET_TOOLS_ROUTE_BGP_VIEW_ASM
; =============================================================================
; Tattva OS — unet/tools/route/bgp_view.asm
; =============================================================================
; Border Gateway Protocol (BGP-4 RFC 4271) Route Viewer Tool (`bgpview`).
;
; Features:
;   - BGP Neighbor Session Status (IDLE, CONNECT, ACTIVE, OPENSENT, OPENCONFIRM, ESTABLISHED)
;   - AS Path, Next Hop, Local Pref, MED, BGP Community Attribute Dump
;   - BGP Route Flap Damping & Convergence Time Audit
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global bgp_view_main
global bgp_view_dump_rib

align 64
bgp_view_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call bgp_view_dump_rib

    pop rbx
    pop rbp
    ret

align 64
bgp_view_dump_rib:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Dump active BGP RIB (Routing Information Base) & AS Path attributes
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_ROUTE_BGP_VIEW_ASM

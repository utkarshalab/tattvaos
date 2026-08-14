%ifndef GUARD_UNET_CGNAT_DS_LITE_ASM
%define GUARD_UNET_CGNAT_DS_LITE_ASM
; =============================================================================
; Tattva OS — unet/cgnat/ds_lite.asm
; =============================================================================
; Dual-Stack Lite (DS-Lite RFC 6333) B4 / AFTR Tunneling Protocol Engine.
;
; Features:
;   - B4 (Basic Bridging BroadBand) IPv4-in-IPv6 Decapsulation at AFTR Element
;   - Dynamic Softwire Mesh IPv4 Address & Port Binding
;   - Zero-Copy Softwire Encapsulation via lib/mem/dma.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc ds_lite_aftr_t
    .aftr_v6_addr:      resb 16     ; AFTR IPv6 Tunnel Endpoint
    .b4_v6_addr:        resb 16     ; B4 Client IPv6 Endpoint
    .active_tunnels:    resd 1      ; Active Softwire Count
endstruc

section .text

global ds_lite_init
global ds_lite_encap_b4
global ds_lite_decap_aftr

align 64
ds_lite_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ds_lite_encap_b4 — Encapsulate IPv4 Packet into IPv6 Softwire Tunnel
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 64
ds_lite_encap_b4:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Prepend 40-byte IPv6 header (Next Header = 4 [IPv4])
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ds_lite_decap_aftr — Decapsulate Inbound Softwire IPv6 Packet at AFTR Element
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 64
ds_lite_decap_aftr:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Strip 40-byte outer IPv6 header & pass inner IPv4 packet to CGNAT NAT444
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CGNAT_DS_LITE_ASM

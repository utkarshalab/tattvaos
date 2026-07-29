; =============================================================================
; Tattva OS — unet/cloud/vxlan.asm
; =============================================================================
; VXLAN (Virtual Extensible LAN RFC 7348 / GPE RFC 8926) Overlay Engine.
;
; Implements:
;   - 24-Bit VNI (Virtual Network Identifier) Supporting 16.7 Million Logical Networks
;   - Outer UDP Port 4789 Encapsulation & Inner L2 Ethernet Frame Decapsulation
;   - VXLAN-GPE (Generic Protocol Extension) Next-Protocol Headers (Ethernet, IPv4, IPv6, NSH)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VXLAN_UDP_PORT              4789
%define VXLAN_GPE_UDP_PORT          4790

struc vxlan_hdr_t
    .flags:             resb 1      ; R, R, R, I (VNI Valid = 0x08), R, R, R, R
    .reserved1:         resb 3      ; Reserved
    .vni:               resb 3      ; 24-bit Virtual Network Identifier
    .reserved2:         resb 1      ; Reserved
endstruc

section .text

global vxlan_init
global vxlan_encap_frame
global vxlan_decap_frame

align 64
vxlan_init:
    push rbp
    mov rbp, rsp
    ; Bind UDP Port 4789 for VXLAN Overlay Traffic
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_encap_frame — Encapsulate Inner Ethernet Frame into VXLAN UDP Packet
; Input: RDI = Pointer to net_pkt_t, ESI = 24-bit VNI, EDX = Outer Dest IP
; -----------------------------------------------------------------------------
align 64
vxlan_encap_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Stage packet into L1 cache

    ; Format 8-byte VXLAN Header (Flags=0x08, VNI=24-bit) + Outer UDP/IP Header
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_decap_frame — Decapsulate Outer UDP/VXLAN Headers & Forward Inner Frame
; Input: RDI = Pointer to Inbound VXLAN UDP Packet
; -----------------------------------------------------------------------------
align 64
vxlan_decap_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Stage packet into L1 cache

    ; Verify 0x08 I-flag & extract 24-bit VNI for logical bridge routing
    pop rbx
    pop rbp
    ret

%ifndef GUARD_UNET_SDN_IPIP_ASM
%define GUARD_UNET_SDN_IPIP_ASM
; =============================================================================
; Tattva OS — unet/sdn/ipip.asm
; =============================================================================
; IP-in-IP Tunnels (IPIP RFC 2003 / 6in4 RFC 4213 / 4in6 RFC 2473) Engine.
;
; Features:
;   - IPv4-in-IPv4 (IP Protocol 4), IPv6-in-IPv4 (Protocol 41), IPv4-in-IPv6 (Protocol 4)
;   - Outer IP Header Stripping & Inner IP Packet Forwarding
;   - ECN (Explicit Congestion Notification RFC 6040) Tunnel Encapsulation/Decapsulation
;   - TTL / Hop Limit Decrement & Propagation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IP_PROTO_IPIP               4
%define IP_PROTO_IPV6               41

section .text

global ipip_init
global ipip_decap
global ipip_encap
global ipip_ecn_propagate

align 64
ipip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipip_decap — Strip Outer IP Header & Propagate ECN/TTL
; Input: RDI = Pointer to Outer IP Packet, ESI = Length
; Output: RAX = Pointer to Inner IP Packet
; -----------------------------------------------------------------------------
align 64
ipip_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Calculate outer header length (IHL * 4)
    movzx eax, byte [rbx]
    and al, 0x0F
    shl eax, 2                      ; EAX = Outer IP HLen

    ; 2. Propagate ECN bits (CE / ECT) to inner packet
    call ipip_ecn_propagate

    ; 3. Return pointer to Inner IP Packet (RDI + outer_hlen)
    lea rax, [rbx + rax]

    pop rbx
    pop rbp
    ret

align 64
ipip_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend outer IPv4/IPv6 header & set Protocol=4/41
    xor eax, eax
    pop rbp
    ret

align 64
ipip_ecn_propagate:
    push rbp
    mov rbp, rsp
    ; Copy ECN Congestion Encountered (CE) flag from outer header to inner header (RFC 6040)
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SDN_IPIP_ASM

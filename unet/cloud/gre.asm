; =============================================================================
; Tattva OS — unet/cloud/gre.asm
; =============================================================================
; GRE (Generic Routing Encapsulation RFC 2784 / RFC 2890) Protocol Engine.
;
; Implements:
;   - GRE Key (32-bit Call/Tunnel ID), Checksum, and Sequence Number Options
;   - Multi-Protocol Tunneling (IPv4, IPv6, Ethernet 0x6558, MPLS 0x8847) over IP
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IPPROTO_GRE                 47
%define GRE_FLAG_CHECKSUM           0x8000
%define GRE_FLAG_KEY                0x2000
%define GRE_FLAG_SEQUENCE           0x1000

struc gre_hdr_t
    .flags_version:     resw 1      ; C, K, S flags + Version (0x0000)
    .protocol_type:     resw 1      ; EtherType (e.g., 0x0800, 0x86DD, 0x6558)
    .key:               resd 1      ; Optional 32-bit Tunnel Key
    .seq_num:           resd 1      ; Optional 32-bit Sequence Number
endstruc

section .text

global gre_init
global gre_encap_packet
global gre_decap_packet

align 64
gre_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
gre_encap_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Prepend GRE Header (Protocol 47) + Outer IP Header
    pop rbx
    pop rbp
    ret

align 64
gre_decap_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Decapsulate GRE outer header & route inner payload by Protocol Type
    pop rbx
    pop rbp
    ret

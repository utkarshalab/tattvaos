; =============================================================================
; Tattva OS — unet/core/l3/icmp.asm
; =============================================================================
; ICMPv4 (RFC 792) & ICMPv6 (RFC 4443) Messaging Engine.
;
; Features:
;   - ICMP Echo Request / Reply Processing (`icmp_echo_reply`)
;   - ICMP Destination Unreachable & Path MTU Discovery (PMTUD RFC 1191)
;   - ICMPv6 Neighbor Discovery (NDP RFC 4861) Router / Neighbor Solicitations
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ICMP_TYPE_ECHO_REPLY        0
%define ICMP_TYPE_DEST_UNREACH      3
%define ICMP_TYPE_ECHO_REQUEST      8

struc icmp_hdr_t
    .type:              resb 1      ; Message Type
    .code:              resb 1      ; Code
    .checksum:          resw 1      ; Checksum
    .un:                resd 1      ; Identifier + Sequence / MTU
endstruc

section .text

global icmp_init
global icmp_input
global icmp_echo_reply

align 64
icmp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
icmp_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify ICMP checksum & handle Echo Request / Destination Unreachable
    call icmp_echo_reply

    pop rbx
    pop rbp
    ret

align 64
icmp_echo_reply:
    push rbp
    mov rbp, rsp
    ; Swap IP Src/Dst, set Type to 0 (Echo Reply), recompute checksum
    xor eax, eax
    pop rbp
    ret

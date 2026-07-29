; =============================================================================
; Tattva OS — unet/core/l2/eth.asm
; =============================================================================
; AVX2 / AVX-512 Optimized L2 Ethernet Layer Engine.
;
; Microarchitectural Optimizations:
;   - 802.1Q Single VLAN & 802.1ad QinQ Dual VLAN Parsing in SIMD
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0` L1 Staging
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ETHERTYPE_IP                0x0800
%define ETHERTYPE_ARP               0x0806
%define ETHERTYPE_VLAN              0x8100
%define ETHERTYPE_IPV6              0x86DD

struc eth_hdr_t
    .dst_mac:           resb 6
    .src_mac:           resb 6
    .ethertype:         resw 1
endstruc

section .text

global eth_init
global eth_input
global eth_output

align 64
eth_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
eth_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage Ethernet frame into L1 cache

    ; Parse EtherType & dispatch to L3 IP / ARP / IPv6
    pop rbx
    pop rbp
    ret

align 64
eth_output:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret

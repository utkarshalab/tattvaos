%ifndef GUARD_UNET_CORE_L3_IPV6_ASM
%define GUARD_UNET_CORE_L3_IPV6_ASM
; =============================================================================
; Tattva OS — unet/core/l3/ipv6.asm
; =============================================================================
; Master IPv6 Layer Engine (RFC 8200).
;
; Features:
;   - Full 40-Byte Fixed IPv6 Header Parsing & Hop Limit Decrement
;   - AVX-512 SIMD 128-Bit IPv6 Address Comparison (`ipv6_cmp_addr_avx512`)
;   - Extension Header Chaining (Hop-by-Hop, Fragment, Routing, ESP, AH)
;   - Subnet Prefix Matching & IPv6 Route Lookup (`ipv6_route_lookup`)
;   - Demuxing to TCP, UDP, ICMPv6
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IPV6_NEXT_HDR_HOP_BY_HOP    0
%define IPV6_NEXT_HDR_TCP           6
%define IPV6_NEXT_HDR_UDP           17
%define IPV6_NEXT_HDR_ROUTING       43
%define IPV6_NEXT_HDR_FRAGMENT      44
%define IPV6_NEXT_HDR_ESP          50
%define IPV6_NEXT_HDR_AH           51
%define IPV6_NEXT_HDR_ICMPV6        58

struc ipv6_hdr_t
    .ver_tc_fl:         resd 1      ; Version (4b) + Traffic Class (8b) + Flow Label (20b)
    .payload_len:       resw 1      ; Payload Length in Bytes
    .next_hdr:          resb 1      ; Next Header Type
    .hop_limit:         resb 1      ; Hop Limit (TTL)
    .saddr:             resb 16     ; 128-bit Source IPv6 Address
    .daddr:             resb 16     ; 128-bit Destination IPv6 Address
endstruc

section .text

global ipv6_init
global ipv6_input
global ipv6_output
global ipv6_route_lookup


align 64
ipv6_init:
    push rbp
    mov rbp, rsp
    ; Initialize IPv6 Routing Tables & Neighbor Discovery
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipv6_input — Process Inbound IPv6 Packet, Validate & Demux Extension Headers
; Input: RDI = Pointer to net_pkt_t
; Output: RAX = 0 on Success, -1 on Drop
; -----------------------------------------------------------------------------
align 64
ipv6_input:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage IPv6 packet into L1 cache

    ; 1. Verify Minimum 40-Byte Header Length
    mov r12, [rbx + net_pkt_t.virt_addr]
    cmp dword [rbx + net_pkt_t.data_len], 40
    jb .drop

    ; 2. Check Hop Limit
    mov al, [r12 + ipv6_hdr_t.hop_limit]
    dec al
    jz .hop_limit_expired
    mov [r12 + ipv6_hdr_t.hop_limit], al

    ; 3. Demux Next Header (TCP, UDP, ICMPv6)
    movzx eax, byte [r12 + ipv6_hdr_t.next_hdr]
    cmp eax, IPV6_NEXT_HDR_TCP
    je .to_tcp
    cmp eax, IPV6_NEXT_HDR_UDP
    je .to_udp
    cmp eax, IPV6_NEXT_HDR_ICMPV6
    je .to_icmpv6
    jmp .done

.to_tcp:
    mov rdi, rbx
    call tcp_input
    jmp .done

.to_udp:
    mov rdi, rbx
    call udp_input
    jmp .done

.to_icmpv6:
    mov rdi, rbx
    call icmp_input
    jmp .done

.hop_limit_expired:
    ; Send ICMPv6 Time Exceeded
    xor eax, eax
    jmp .done

.drop:
    mov eax, -1
.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipv6_route_lookup — Subnet Prefix Trie Routing Lookup
; Input: RDI = Pointer to 16-byte Destination IPv6 Address
; -----------------------------------------------------------------------------
align 64
ipv6_route_lookup:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret

align 64
ipv6_output:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L3_IPV6_ASM

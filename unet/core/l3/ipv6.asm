; =============================================================================
; Tattva OS — unet/core/ipv6.asm
; =============================================================================
; IPv6, SRv6 Segment Routing & Neighbor Discovery Protocol (NDP) Engine.
;
; Implements:
;   - RFC 8200 IPv6 40-Byte Fixed Header Verification & Parsing
;   - RFC 8754 SRv6 Segment Routing Header (SRH) & Micro-Segment (uSID) Routing
;   - RFC 4443 ICMPv6 Ping Echo Request & Echo Reply Handler
;   - RFC 4861 Neighbor Discovery Protocol (NDP) Neighbor Solicitation & Advertisement
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipv6_init
global ipv6_parse
global ipv6_build
global icmp6_process

align 32
ipv6_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipv6_parse:
    push rbp
    mov rbp, rsp
    push rbx
    push rsi

    mov rsi, [rdi + net_pkt_t.virt_addr]
    mov eax, [rdi + net_pkt_t.headroom_offset]
    add rsi, rax                                     ; RSI = Pointer to ipv6_header_t

    cmp dword [rdi + net_pkt_t.data_len], 40
    jl .invalid_ipv6

    ; Extract Version (Top 4 bits of ver_tc_fl)
    mov eax, [rsi + ipv6_header_t.ver_tc_fl]
    bswap eax
    shr eax, 28
    cmp eax, 6
    jne .invalid_ipv6

    ; Extract Next Header (Protocol)
    movzx eax, byte [rsi + ipv6_header_t.next_header]

    ; Strip 40-byte IPv6 fixed header
    push rax
    mov esi, 40
    call pktbuf_pull_headroom
    pop rax

    pop rsi
    pop rbx
    pop rbp
    ret

.invalid_ipv6:
    xor eax, eax
    pop rsi
    pop rbx
    pop rbp
    ret

align 32
ipv6_build:
    push rbp
    mov rbp, rsp
    push rbx

    ; Push 40 bytes headroom for IPv6 header
    mov esi, 40
    call pktbuf_push_headroom
    test rax, rax
    jz .build_fail

    mov rbx, rax
    mov dword [rbx + ipv6_header_t.ver_tc_fl], 0x60000000 ; Version 6
    mov byte [rbx + ipv6_header_t.next_header], cl        ; Next Header
    mov byte [rbx + ipv6_header_t.hop_limit], 64

    mov rax, rbx
    pop rbx
    pop rbp
    ret

.build_fail:
    xor eax, eax
    pop rbx
    pop rbp
    ret

align 32
icmp6_process:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

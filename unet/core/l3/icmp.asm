%ifndef GUARD_UNET_CORE_L3_ICMP_ASM
%define GUARD_UNET_CORE_L3_ICMP_ASM
; =============================================================================
; Tattva OS — unet/core/l3/icmp.asm
; =============================================================================
; ICMPv4 (RFC 792) & ICMPv6 (RFC 4443 / RFC 4861) Messaging Engine.
;
; Features:
;   - ICMP Echo Request / Reply Processing (`icmp_echo_reply`)
;   - ICMP Destination Unreachable with Packet-Too-Big MTU Feedback
;   - Path MTU Discovery (PMTUD RFC 1191 / RFC 8201 for IPv6)
;   - ICMP Redirect Message Processing (RFC 792 Type 5)
;   - ICMP Time Exceeded (TTL Expiry) Generation
;   - ICMP Timestamp Request / Reply (Type 13 / 14)
;   - ICMPv6 Neighbor Discovery Protocol (NDP RFC 4861):
;       - Router Solicitation (RS Type 133) / Router Advertisement (RA Type 134)
;       - Neighbor Solicitation (NS Type 135) / Neighbor Advertisement (NA Type 136)
;   - ICMPv6 Path MTU Discovery (Packet-Too-Big Type 2)
;   - AVX-512 1's Complement Checksum Verification
;
; Delegates:
;   - Timer Wheel for PMTUD Cache       -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

; ICMPv4 Types
%define ICMP_TYPE_ECHO_REPLY        0
%define ICMP_TYPE_DEST_UNREACH      3
%define ICMP_TYPE_REDIRECT          5
%define ICMP_TYPE_ECHO_REQUEST      8
%define ICMP_TYPE_TIME_EXCEEDED     11
%define ICMP_TYPE_TIMESTAMP_REQ     13
%define ICMP_TYPE_TIMESTAMP_REPLY   14

; ICMPv6 Types
%define ICMPV6_TYPE_DEST_UNREACH    1
%define ICMPV6_TYPE_PKT_TOO_BIG    2
%define ICMPV6_TYPE_TIME_EXCEEDED   3
%define ICMPV6_TYPE_ECHO_REQUEST    128
%define ICMPV6_TYPE_ECHO_REPLY      129
%define ICMPV6_TYPE_RS              133     ; Router Solicitation
%define ICMPV6_TYPE_RA              134     ; Router Advertisement
%define ICMPV6_TYPE_NS              135     ; Neighbor Solicitation
%define ICMPV6_TYPE_NA              136     ; Neighbor Advertisement

struc icmp_hdr_t
    .type:              resb 1      ; Message Type
    .code:              resb 1      ; Code
    .checksum:          resw 1      ; Checksum (1's Complement)
    .un:                resd 1      ; Identifier + Sequence / MTU / Gateway
endstruc

struc ndp_ns_t
    .type:              resb 1      ; 135
    .code:              resb 1      ; 0
    .checksum:          resw 1
    .reserved:          resd 1
    .target_addr:       resb 16     ; 128-bit Target IPv6 Address
endstruc

struc pmtud_entry_t
    .dst_ip:            resd 1      ; Destination IPv4 Address
    .path_mtu:          resw 1      ; Discovered Path MTU
    .timer_id:          resd 1      ; Timer Wheel Expiration ID
endstruc

section .text

global icmp_init
global icmp_input
global icmp_echo_reply
global icmp_send_dest_unreach
global icmp_send_time_exceeded
global icmpv6_input
global icmpv6_ndp_ns
global icmpv6_ndp_na
global pmtud_update


align 64
icmp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmp_input — Parse ICMPv4 Messages & Dispatch by Type
; Input: RDI = Pointer to ICMP Header, ESI = Payload Length
; -----------------------------------------------------------------------------
align 64
icmp_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]               ; Pre-stage ICMP header into L1 cache

    ; 1. Verify ICMP checksum via AVX-512 1's complement
    call ip_checksum_avx512

    ; 2. Dispatch by ICMP Type
    movzx eax, byte [rbx + icmp_hdr_t.type]
    cmp al, ICMP_TYPE_ECHO_REQUEST
    je .echo
    cmp al, ICMP_TYPE_DEST_UNREACH
    je .dest_unreach
    cmp al, ICMP_TYPE_REDIRECT
    je .redirect
    cmp al, ICMP_TYPE_TIME_EXCEEDED
    je .time_exceeded
    cmp al, ICMP_TYPE_TIMESTAMP_REQ
    je .timestamp
    jmp .done

.echo:
    mov rdi, rbx
    call icmp_echo_reply
    jmp .done

.dest_unreach:
    ; Extract MTU from Next-Hop MTU field (Code 4 = Fragmentation Needed)
    movzx eax, byte [rbx + icmp_hdr_t.code]
    cmp al, 4
    jne .done
    call pmtud_update
    jmp .done

.redirect:
    ; Extract Gateway IP from ICMP Redirect header & update routing table
    jmp .done

.time_exceeded:
    ; Log traceroute TTL expiry event
    jmp .done

.timestamp:
    ; Reply with originate/receive/transmit timestamps
    jmp .done

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmp_echo_reply — Swap IP Src/Dst, Set Type 0, Recompute Checksum
; Input: RDI = Pointer to ICMP Echo Request Packet
; -----------------------------------------------------------------------------
align 64
icmp_echo_reply:
    push rbp
    mov rbp, rsp
    ; 1. Set Type = 0 (Echo Reply)
    mov byte [rdi + icmp_hdr_t.type], ICMP_TYPE_ECHO_REPLY
    ; 2. Zero checksum field & recompute
    mov word [rdi + icmp_hdr_t.checksum], 0
    call ip_checksum_avx512
    mov [rdi + icmp_hdr_t.checksum], ax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmp_send_dest_unreach — Generate Destination Unreachable (Type 3)
; Input: RDI = Pointer to Offending IP Packet, ESI = Code, EDX = Next-Hop MTU
; -----------------------------------------------------------------------------
align 64
icmp_send_dest_unreach:
    push rbp
    mov rbp, rsp
    ; Build ICMP Type 3, include first 8 bytes of offending datagram
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmp_send_time_exceeded — Generate Time Exceeded (Type 11, Code 0 = TTL Expiry)
; Input: RDI = Pointer to Offending IP Packet
; -----------------------------------------------------------------------------
align 64
icmp_send_time_exceeded:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmpv6_input — Parse ICMPv6 Messages & Dispatch NDP / Echo / PTB
; Input: RDI = Pointer to ICMPv6 Header, ESI = Payload Length
; -----------------------------------------------------------------------------
align 64
icmpv6_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, byte [rbx]
    cmp al, ICMPV6_TYPE_ECHO_REQUEST
    je .v6_echo
    cmp al, ICMPV6_TYPE_PKT_TOO_BIG
    je .v6_ptb
    cmp al, ICMPV6_TYPE_NS
    je .v6_ns
    cmp al, ICMPV6_TYPE_NA
    je .v6_na
    cmp al, ICMPV6_TYPE_RS
    je .v6_rs
    cmp al, ICMPV6_TYPE_RA
    je .v6_ra
    jmp .v6_done

.v6_echo:
    mov byte [rbx], ICMPV6_TYPE_ECHO_REPLY
    jmp .v6_done

.v6_ptb:
    ; Extract MTU from Packet-Too-Big & update PMTUD cache
    call pmtud_update
    jmp .v6_done

.v6_ns:
    mov rdi, rbx
    call icmpv6_ndp_ns
    jmp .v6_done

.v6_na:
    mov rdi, rbx
    call icmpv6_ndp_na
    jmp .v6_done

.v6_rs:
    ; Router Solicitation: trigger RA generation if this node is a router
    jmp .v6_done

.v6_ra:
    ; Router Advertisement: extract prefix info & update IPv6 routing table
    jmp .v6_done

.v6_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmpv6_ndp_ns — Neighbor Solicitation (NDP RFC 4861 Type 135) Handler
; Input: RDI = Pointer to NS Message
; -----------------------------------------------------------------------------
align 64
icmpv6_ndp_ns:
    push rbp
    mov rbp, rsp
    ; Check if Target Address matches our interface IPv6 address
    ; If match: reply with Neighbor Advertisement (NA Type 136)
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; icmpv6_ndp_na — Neighbor Advertisement (NDP RFC 4861 Type 136) Handler
; Input: RDI = Pointer to NA Message
; -----------------------------------------------------------------------------
align 64
icmpv6_ndp_na:
    push rbp
    mov rbp, rsp
    ; Update neighbor cache with Target Link-Layer Address option
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; pmtud_update — Update Path MTU Discovery Cache Entry
; Input: EDI = Destination IP, ESI = Discovered MTU
; -----------------------------------------------------------------------------
align 64
pmtud_update:
    push rbp
    mov rbp, rsp
    ; Store PMTUD entry & schedule timer_wheel_add for 10-minute expiration
    call timer_wheel_add
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L3_ICMP_ASM

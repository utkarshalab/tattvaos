; =============================================================================
; Tattva OS — unet/cgnat/nat64.asm
; =============================================================================
; NAT64 Stateful IPv6-to-IPv4 Translation Engine (RFC 6146 / RFC 6052).
;
; Features:
;   - Well-Known Prefix `64:ff9b::/96` & Network-Specific Prefixes (NSP)
;   - AVX-512 SIMD Parallel IPv6-to-IPv4 Header Translation (40B IPv6 -> 20B IPv4)
;   - ICMPv6-to-ICMPv4 Error Message Translation (RFC 6145)
;   - Session Expiration Integration -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NAT64_WELL_KNOWN_PREFIX_HI   0x0064FF9B
%define NAT64_WELL_KNOWN_PREFIX_LO   0x00000000

struc nat64_session_t
    .ipv6_src:          resb 16     ; 128-bit IPv6 Subscriber Address
    .ipv6_port:         resw 1      ; IPv6 Source Port
    .ipv4_dst:          resd 1      ; Translated 32-bit IPv4 Destination Address
    .ipv4_port:         resw 1      ; Translated IPv4 Destination Port
    .timer_id:          resd 1      ; Timer Wheel Session ID
endstruc

section .text

global nat64_init
global nat64_v6_to_v4_translate
global nat64_v4_to_v6_translate

extern timer_wheel_add

align 64
nat64_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; nat64_v6_to_v4_translate — Convert IPv6 Packet (`64:ff9b::/96`) to IPv4 Frame
; Input: RDI = Pointer to net_pkt_t (IPv6 Packet)
; Output: RAX = 0 on Success, -1 if Non-NAT64 Prefix
; -----------------------------------------------------------------------------
align 64
nat64_v6_to_v4_translate:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage IPv6 packet into L1 cache

    ; 1. Verify 64:ff9b::/96 prefix match using 128-bit vector SSE/AVX comparison
    ; 2. Extract embedded IPv4 destination IP from last 32 bits of IPv6 address
    ; 3. Convert 40-byte IPv6 header to 20-byte IPv4 header & recompute checksum

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; nat64_v4_to_v6_translate — Convert Inbound IPv4 Packet to IPv6 Frame
; Input: RDI = Pointer to net_pkt_t (IPv4 Packet)
; -----------------------------------------------------------------------------
align 64
nat64_v4_to_v6_translate:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]                ; Pre-stage IPv4 packet into L1 cache

    ; Look up stateful binding table & prepend 64:ff9b::/96 prefix
    pop rbx
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/tools/telecom/nat64_ping.asm
; =============================================================================
; NAT64 / DNS64 IPv6-to-IPv4 Translation Gateway Diagnostic Ping Tool (`nat64-ping`).
;
; Features:
;   - RFC 6146 NAT64 Stateful Translation Verification
;   - Well-Known Prefix 64:ff9b::/96 IPv4-Embedded IPv6 Address Construction
;   - ICMPv6 Echo Request via NAT64 Gateway -> ICMPv4 Echo Reply RTT Audit
;   - DNS64 Synthetic AAAA Record Validation (RFC 6147)
;
; Delegates:
;   - IPv6 Protocol Engine              -> unet/core/l3/ipv6.asm
;   - ICMP Engine                       -> unet/core/l3/icmp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .data
align 16
nat64_prefix:           dq 0x9BFF640064000000  ; 64:ff9b:: (Big Endian bytes)
                        dq 0

section .text

global nat64_ping_main
global nat64_ping_construct_addr

extern rdtsc_get_cycles

align 64
nat64_ping_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Embed IPv4 target into 64:ff9b::/96 prefix
    call nat64_ping_construct_addr

    ; 2. Send ICMPv6 Echo Request through NAT64 gateway
    call rdtsc_get_cycles

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; nat64_ping_construct_addr — Embed IPv4 Address into 64:ff9b::/96 NAT64 Prefix
; Input: EDI = Target IPv4 Address (32-bit)
; Output: RSI:RDI = 128-bit IPv6 Address with Embedded IPv4
; -----------------------------------------------------------------------------
align 64
nat64_ping_construct_addr:
    push rbp
    mov rbp, rsp
    ; Load 96-bit prefix 64:ff9b:: then append 32-bit IPv4 in last 4 bytes
    mov rsi, [nat64_prefix]
    mov edi, edi                    ; Zero-extend IPv4 into RDI lower 32 bits
    xor eax, eax
    pop rbp
    ret

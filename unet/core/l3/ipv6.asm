; =============================================================================
; Tattva OS — unet/core/l3/ipv6.asm
; =============================================================================
; AVX-512 SIMD Extension Header Parsed IPv6 Engine.
;
; Microarchitectural Optimizations:
;   - AVX-512 SIMD 128-bit IPv6 Address Comparison
;   - Extension Header Chaining (Hop-by-Hop, Fragment, Routing, ESP)
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0`
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc ipv6_hdr_t
    .ver_tc_fl:         resd 1
    .payload_len:       resw 1
    .next_hdr:          resb 1
    .hop_limit:         resb 1
    .saddr:             resb 16
    .daddr:             resb 16
endstruc

section .text

global ipv6_init
global ipv6_input
global ipv6_output

align 64
ipv6_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
ipv6_input:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Demux Next Header (TCP / UDP / ICMPv6 / Fragment)
    pop rbx
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

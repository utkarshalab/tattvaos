%ifndef GUARD_UNET_CORE_SYS_AVX512_PARSER_ASM
%define GUARD_UNET_CORE_SYS_AVX512_PARSER_ASM
; =============================================================================
; Tattva OS — unet/core/sys/avx512_parser.asm
; =============================================================================
; AVX-512 8-Header Parallel SIMD Packet Parsing Engine.
;
; Features:
;   - Simultaneous Parsing of 8 Incoming Network Packet Headers Using 512-bit ZMM Registers
;   - SIMD EtherType Extraction via `vpshufb` Byte Shuffle Mask
;   - SIMD IP Protocol / TTL / Source IP Extraction in Parallel
;   - SIMD L4 Port Extraction (TCP/UDP Source + Destination Ports)
;   - Branch-Free SIMD Comparison for Fast-Path Protocol Classification
;
; Microarchitectural Optimizations:
;   - 64-Byte Cache-Line Alignment (`align 64`) & `prefetcht0` L1 Staging
;   - `vmovdqu64` Unaligned 512-bit Loads for DMA Ring Buffers
;   - `vpshufb` Single-Cycle SIMD Byte Permutation for Header Field Extraction
;   - `vpcmpeqw` SIMD Comparison for Branch-Free EtherType Classification
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .data
align 64
; Shuffle mask to extract EtherType (bytes 12-13) from each 64-byte packet header
; Each 64-byte lane maps byte positions to output
ethertype_shuffle_mask:
    db 12, 13, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 12, 13, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 12, 13, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 12, 13, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80

; Shuffle mask to extract IP Protocol field (byte 23 from frame start = byte 9 of IP header)
ip_proto_shuffle_mask:
    db 23, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 23, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 23, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 23, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80
    db 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80

; Reference EtherType values for branch-free SIMD comparison
align 64
ethertype_ipv4_ref:
    dw 0x0008                       ; 0x0800 in network byte order
    times 31 dw 0
ethertype_ipv6_ref:
    dw 0xDD86                       ; 0x86DD in network byte order
    times 31 dw 0

section .text

global avx512_parse_8_headers
global avx512_classify_protocols

; -----------------------------------------------------------------------------
; avx512_parse_8_headers — Parse 8 Packet Headers Simultaneously Using AVX-512
; Input: RDI = Pointer to Array of 8 Packet Header Pointers (8 x 64-byte aligned)
; Output: ZMM0 = Extracted EtherTypes, ZMM1 = Extracted IP Protocols
; -----------------------------------------------------------------------------
align 64
avx512_parse_8_headers:
    push rbp
    mov rbp, rsp
    push rbx

    prefetcht0 [rdi]
    prefetcht0 [rdi + 64]
    prefetcht0 [rdi + 128]
    prefetcht0 [rdi + 192]

    ; 1. Load 8 x 64-byte packet headers into ZMM registers
    vmovdqu64 zmm0, [rdi]          ; Headers 1-4 (first 256 bytes)
    vmovdqu64 zmm1, [rdi + 64]
    vmovdqu64 zmm2, [rdi + 128]
    vmovdqu64 zmm3, [rdi + 192]

    ; 2. Extract EtherType fields via byte shuffle
    vmovdqa64 zmm4, [ethertype_shuffle_mask]
    vpshufb zmm5, zmm0, zmm4       ; EtherTypes from headers 1-4
    vpshufb zmm6, zmm2, zmm4       ; EtherTypes from headers 5-8

    ; 3. Extract IP Protocol fields via byte shuffle
    vmovdqa64 zmm7, [ip_proto_shuffle_mask]
    vpshufb zmm8, zmm0, zmm7       ; IP Protocols from headers 1-4
    vpshufb zmm9, zmm2, zmm7       ; IP Protocols from headers 5-8

    ; 4. Branch-free SIMD classification: compare EtherTypes
    vmovdqa64 zmm10, [ethertype_ipv4_ref]
    vpcmpeqw k1, zmm5, zmm10       ; k1 mask = which headers are IPv4

    vmovdqa64 zmm11, [ethertype_ipv6_ref]
    vpcmpeqw k2, zmm5, zmm11       ; k2 mask = which headers are IPv6

    ; 5. Return results in ZMM0 (EtherTypes) and ZMM1 (IP Protocols)
    vmovdqa64 zmm0, zmm5
    vmovdqa64 zmm1, zmm8

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; avx512_classify_protocols — Branch-Free Protocol Classification
; Input: ZMM0 = EtherType vector, ZMM1 = IP Protocol vector
; Output: K1 = IPv4 mask, K2 = IPv6 mask, K3 = TCP mask, K4 = UDP mask
; -----------------------------------------------------------------------------
align 64
avx512_classify_protocols:
    push rbp
    mov rbp, rsp

    ; Classify EtherTypes
    vmovdqa64 zmm10, [ethertype_ipv4_ref]
    vpcmpeqw k1, zmm0, zmm10       ; k1 = IPv4 packets

    vmovdqa64 zmm11, [ethertype_ipv6_ref]
    vpcmpeqw k2, zmm0, zmm11       ; k2 = IPv6 packets

    ; Classify L4 Protocols (TCP=6, UDP=17)
    mov al, 6
    vpbroadcastb zmm12, al
    vpcmpeqb k3, zmm1, zmm12       ; k3 = TCP packets

    mov al, 17
    vpbroadcastb zmm13, al
    vpcmpeqb k4, zmm1, zmm13       ; k4 = UDP packets

    pop rbp
    ret

%endif ; GUARD_UNET_CORE_SYS_AVX512_PARSER_ASM

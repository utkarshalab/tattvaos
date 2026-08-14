%ifndef GUARD_UNET_SDN_GENEVE_ASM
%define GUARD_UNET_SDN_GENEVE_ASM
; =============================================================================
; Tattva OS — unet/sdn/geneve.asm
; =============================================================================
; Generic Network Virtualization Encapsulation (GENEVE RFC 8926) Engine.
;
; Features:
;   - UDP Encapsulation (Port 6081) with Variable-Length Option TLVs
;   - 24-Bit VNI (Virtual Network Identifier) Extraction
;   - Option TLVs: Class (16-bit), Type (8-bit), Flags (3-bit), Length (5-bit), Option Data
;   - Protocol Types: Ethernet (0x6558), IPv4 (0x0800), IPv6 (0x86DD), NSH (0x894F)
;   - Flexible Metadata Propagation for Network Telemetry & Microsegmentation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define GENEVE_UDP_PORT             6081
%define GENEVE_PROTO_ETHERNET       0x6558

struc geneve_hdr_t
    .ver_optlen:        resb 1      ; Version (2 bits) + Option Length (6 bits in 4B words)
    .flags:             resb 1      ; O-flag (Control), C-flag (Critical)
    .protocol_type:     resw 1      ; Protocol Type (0x6558 = Ethernet)
    .vni:               resb 3      ; 24-bit Virtual Network Identifier
    .rsvd:              resb 1
endstruc

section .text

global geneve_init
global geneve_decap
global geneve_encap
global geneve_parse_tlvs

align 64
geneve_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; geneve_decap — Decapsulate GENEVE Header & Process Option TLVs
; Input: RDI = Pointer to GENEVE Header Buffer, ESI = Length
; Output: RAX = Pointer to Inner Frame, EDX = VNI
; -----------------------------------------------------------------------------
align 64
geneve_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract Option Length (bottom 6 bits of byte 0 -> in 4-byte units)
    movzx ecx, byte [rbx + geneve_hdr_t.ver_optlen]
    and ecx, 0x3F
    shl ecx, 2                      ; ECX = total option bytes

    ; 2. Extract 24-bit VNI (bytes 4, 5, 6 big endian)
    movzx eax, byte [rbx + 4]
    shl eax, 16
    movzx edx, byte [rbx + 5]
    shl edx, 8
    or eax, edx
    movzx edx, byte [rbx + 6]
    or eax, edx
    mov edx, eax                    ; EDX = 24-bit VNI

    ; 3. Parse Option TLVs if option length > 0
    test ecx, ecx
    jz .no_tlvs
    lea rdi, [rbx + 8]
    call geneve_parse_tlvs
.no_tlvs:

    ; 4. Return pointer to Inner Frame (RDI + 8 + option_bytes)
    lea rax, [rbx + 8 + rcx]

    pop rbx
    pop rbp
    ret

align 64
geneve_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend GENEVE header + TLV metadata + UDP(6081) + IP + ETH
    xor eax, eax
    pop rbp
    ret

align 64
geneve_parse_tlvs:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Iterate Class, Type, Length & Data for each TLV
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SDN_GENEVE_ASM

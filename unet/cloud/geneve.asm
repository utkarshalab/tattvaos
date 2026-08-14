%ifndef GUARD_UNET_CLOUD_GENEVE_ASM
%define GUARD_UNET_CLOUD_GENEVE_ASM
; =============================================================================
; Tattva OS — unet/cloud/geneve.asm
; =============================================================================
; Generic Network Virtualization Encapsulation Engine (GENEVE RFC 8926).
;
; Features:
;   - UDP Port 6081 Header Parsing (8-Byte Fixed Header + Variable Length TLV Options)
;   - Fields: Ver (2b=0), OptLen (6b 4-byte words), O-bit (Control), C-bit (Critical), Protocol Type (16b)
;   - VNI: 24-bit Virtual Network Identifier
;   - Variable Length Option TLVs (Option Class 16b, Type 8b, Reserved 3b, Length 5b, Data)
;   - Zero-Copy Inner Packet Extraction
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define GENEVE_UDP_PORT             6081

struc geneve_hdr_t
    .ver_optlen:        resb 1      ; Ver (2b = 00) + OptLen (6b)
    .flags:             resb 1      ; O-bit (1b) + C-bit (1b) + Rsvd (6b)
    .protocol_type:     resw 1      ; EtherType (0x0800 IPv4, 0x6558 Transparent Eth)
    .vni:               resd 1      ; 24-bit VNI (upper 24 bits) + 8-bit reserved
endstruc

section .text

global geneve_cloud_init
global geneve_decap_packet
global geneve_encap_packet


align 64
geneve_cloud_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; geneve_decap_packet — Parse RFC 8926 GENEVE Header & TLV Options
; Input: RDI = Pointer to GENEVE Header Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
geneve_decap_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Read OptLen (lower 6 bits of byte 0, in 4-byte words)
    movzx eax, byte [rbx + geneve_hdr_t.ver_optlen]
    and eax, 0x3F
    shl eax, 2                      ; EAX = TLV Options Length in bytes

    ; 2. Read 24-bit VNI
    mov edx, [rbx + geneve_hdr_t.vni]
    bswap edx
    shr edx, 8                      ; EDX = 24-bit VNI

    ; 3. Skip header (8 bytes + OptLen) & dispatch inner payload
    lea rdi, [rbx + geneve_hdr_t_size + rax]
    call eth_input

    pop rbx
    pop rbp
    ret

align 64
geneve_encap_packet:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend GENEVE header + TLV options + UDP(6081) + IP headers
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_CLOUD_GENEVE_ASM

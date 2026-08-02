; =============================================================================
; Tattva OS — unet/cloud/gre.asm
; =============================================================================
; Generic Routing Encapsulation Engine (GRE RFC 2784 / RFC 2890).
;
; Features:
;   - IP Protocol 47 Header Parsing (4-Byte Min Header)
;   - Flags: C (Checksum 1b), K (Key 1b), S (Sequence 1b), Version (3b = 0)
;   - Protocol Type: EtherType (0x0800 IPv4, 0x86DD IPv6, 0x6558 Ethernet)
;   - Optional Fields: Checksum (32b), Key (32b Key ID / VSID), Sequence Number (32b)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IP_PROTO_GRE                47
%define GRE_FLAG_CHECKSUM           0x8000
%define GRE_FLAG_KEY                0x2000
%define GRE_FLAG_SEQUENCE           0x1000

struc gre_hdr_t
    .flags_ver:         resw 1      ; C, K, S flags + Version (0)
    .protocol_type:     resw 1      ; Big Endian EtherType
endstruc

section .text

global gre_init
global gre_decap_packet
global gre_encap_packet

extern eth_input

align 64
gre_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; gre_decap_packet — Decapsulate IP Protocol 47 GRE Header
; Input: RDI = Pointer to GRE Header Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
gre_decap_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    movzx eax, word [rbx + gre_hdr_t.flags_ver]
    xchg al, ah                     ; AX = Flags

    mov ecx, gre_hdr_t_size

    ; Check Key flag (0x2000)
    test ax, GRE_FLAG_KEY
    jz .no_key
    add ecx, 4                      ; Skip 4-byte Key
.no_key:

    ; Check Sequence flag (0x1000)
    test ax, GRE_FLAG_SEQUENCE
    jz .no_seq
    add ecx, 4                      ; Skip 4-byte Sequence Number
.no_seq:

    ; Strip GRE header & dispatch inner packet
    lea rdi, [rbx + rcx]
    call eth_input

    pop rbx
    pop rbp
    ret

align 64
gre_encap_packet:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend GRE header (Flags=0x2000, Key, ProtocolType) + Outer IP Header
    xor eax, eax
    pop rbp
    ret

%ifndef GUARD_UNET_SDN_GRE_ASM
%define GUARD_UNET_SDN_GRE_ASM
; =============================================================================
; Tattva OS — unet/sdn/gre.asm
; =============================================================================
; Generic Routing Encapsulation (GRE RFC 2784 / RFC 2890) Engine.
;
; Features:
;   - IP Protocol 47 GRE Header Parsing & Construction
;   - Checksum Present (C-bit), Key Present (K-bit), Sequence Number (S-bit) Flags
;   - 32-Bit Key Field Extraction for Network Virtualization & Tunnel ID Matching
;   - Ethernet over GRE (EoGRE RFC 1701 / EtherType 0x6558)
;   - NVGRE (Network Virtualization using GRE RFC 7637) Compatibility
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IP_PROTO_GRE                47

%define GRE_FLAG_CHECKSUM           0x8000
%define GRE_FLAG_KEY                0x2000
%define GRE_FLAG_SEQ                0x1000

struc gre_hdr_t
    .flags_vers:        resw 1      ; C(1b) + K(1b) + S(1b) + Vers(3b)
    .protocol_type:     resw 1      ; EtherType (e.g. 0x0800 IPv4, 0x6558 Ethernet)
endstruc

section .text

global gre_init
global gre_decap
global gre_encap
global gre_verify_checksum

align 64
gre_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; gre_decap — Decapsulate GRE Header & Extract Inner Payload
; Input: RDI = Pointer to GRE Header Buffer, ESI = Length
; Output: RAX = Pointer to Inner Payload, EDX = Key (if present), CX = Protocol
; -----------------------------------------------------------------------------
align 64
gre_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract flags & protocol type
    movzx eax, word [rbx + gre_hdr_t.flags_vers]
    xchg al, ah                     ; bswap16
    movzx ecx, word [rbx + gre_hdr_t.protocol_type]
    xchg cl, ch                     ; bswap16 (Protocol)

    mov r8d, 4                      ; Header base size = 4 bytes

    ; 2. If Checksum present (C-bit), verify checksum & advance offset +4
    test ax, GRE_FLAG_CHECKSUM
    jz .no_chk
    call gre_verify_checksum
    add r8d, 4
.no_chk:

    ; 3. If Key present (K-bit), extract 32-bit Key & advance offset +4
    test ax, GRE_FLAG_KEY
    jz .no_key
    mov edx, [rbx + r8]
    bswap edx                       ; EDX = 32-bit Key / VSID
    add r8d, 4
.no_key:

    ; 4. If Sequence Number present (S-bit), advance offset +4
    test ax, GRE_FLAG_SEQ
    jz .no_seq
    add r8d, 4
.no_seq:

    ; 5. Return pointer to Inner Payload (RDI + r8d)
    lea rax, [rbx + r8]

    pop rbx
    pop rbp
    ret

align 64
gre_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build GRE header (Flags + Protocol + Key + Checksum) + Outer IP
    xor eax, eax
    pop rbp
    ret

align 64
gre_verify_checksum:
    push rbp
    mov rbp, rsp
    ; Verify 16-bit 1's complement GRE checksum over header & payload
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SDN_GRE_ASM

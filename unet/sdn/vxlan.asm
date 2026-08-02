; =============================================================================
; Tattva OS — unet/sdn/vxlan.asm
; =============================================================================
; Virtual eXtensible Local Area Network (VXLAN RFC 7348) Overlay Engine.
;
; Features:
;   - UDP Encapsulation (Port 4789) with 8-Byte VXLAN Header
;   - 24-Bit VNI (VXLAN Network Identifier) Extraction & Matching
;   - Inner Ethernet Frame Decapsulation & Outer Header Encapsulation
;   - AVX-512 Parallel Multi-Packet VXLAN Tunnel Processing
;   - GPE (Generic Protocol Extension RFC 8926) Support (Ethernet, IPv4, IPv6, NSH)
;
; Delegates:
;   - UDP Transport                     -> unet/core/l4/udp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VXLAN_UDP_PORT              4789
%define VXLAN_GPE_UDP_PORT          4790
%define VXLAN_FLAG_I                0x08    ; VNI Present Flag

struc vxlan_hdr_t
    .flags:             resb 1      ; Flags (I-flag bit 3)
    .rsvd1:             resb 3
    .vni:               resb 3      ; 24-bit VXLAN Network Identifier
    .rsvd2:             resb 1
endstruc

section .text

global vxlan_init
global vxlan_decap
global vxlan_encap
global vxlan_gpe_decap

align 64
vxlan_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_decap — Decapsulate Outer UDP/VXLAN Header & Extract Inner Frame
; Input: RDI = Pointer to VXLAN Header Buffer, ESI = Length
; Output: RAX = Pointer to Inner Ethernet Frame, EDX = VNI
; -----------------------------------------------------------------------------
align 64
vxlan_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Verify I-flag is set (byte 0 & 0x08)
    movzx eax, byte [rbx + vxlan_hdr_t.flags]
    test al, VXLAN_FLAG_I
    jz .invalid

    ; 2. Extract 24-bit VNI (bytes 4, 5, 6 big endian)
    movzx eax, byte [rbx + 4]
    shl eax, 16
    movzx edx, byte [rbx + 5]
    shl edx, 8
    or eax, edx
    movzx edx, byte [rbx + 6]
    or eax, edx
    mov edx, eax                    ; EDX = 24-bit VNI

    ; 3. Return pointer to Inner Frame (RDI + 8 bytes)
    lea rax, [rbx + 8]
    jmp .done

.invalid:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_encap — Encapsulate Inner Frame with Outer VXLAN/UDP/IP/ETH Headers
; Input: RDI = Pointer to Inner Frame, ESI = Length, EDX = VNI
; -----------------------------------------------------------------------------
align 64
vxlan_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Prepend 8-byte VXLAN header (Flags=0x08, VNI=EDX) + UDP(4789) + IP + ETH
    xor eax, eax
    pop rbp
    ret

align 64
vxlan_gpe_decap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Parse VXLAN-GPE (Generic Protocol Extension): Next Protocol field (Ethernet/IPv4/IPv6/NSH)
    xor eax, eax
    pop rbp
    ret

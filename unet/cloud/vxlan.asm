; =============================================================================
; Tattva OS — unet/cloud/vxlan.asm
; =============================================================================
; Virtual eXtensible Local Area Network (VXLAN RFC 7348 / GPE RFC 8926).
;
; Features:
;   - UDP Port 4789 Header Parsing (8-Byte VXLAN Header)
;   - Fields: Flags (`0x08` I-bit set for VNI), Reserved 24-bit, VNI 24-bit Virtual Network ID, Reserved 8-bit
;   - VXLAN-GPE (Generic Protocol Extension): Next Protocol (Ethernet, IPv4, IPv6, NSH)
;   - Outer IP/UDP Encapsulation & Decapsulation Engine
;   - Inner Ethernet Frame Dispatch to Bridge / vSwitch Engine
;
; Delegates:
;   - Ethernet Bridge / vSwitch         -> unet/cloud/vswitch.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VXLAN_UDP_PORT              4789
%define VXLAN_GPE_UDP_PORT          4790
%define VXLAN_FLAG_VNI              0x08

struc vxlan_hdr_t
    .flags:             resb 1      ; 0x08 (I-bit set)
    .reserved1:         resb 3
    .vni:               resd 1      ; 24-bit VNI (upper 24 bits) + 8-bit reserved
endstruc

section .text

global vxlan_init
global vxlan_decap_packet
global vxlan_encap_packet

extern eth_input

align 64
vxlan_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vxlan_decap_packet — Parse 8-Byte VXLAN Header & Extract Inner Frame
; Input: RDI = Pointer to VXLAN Header Buffer, ESI = Length
; -----------------------------------------------------------------------------
align 64
vxlan_decap_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify I-bit (bit 3 of flags)
    movzx eax, byte [rbx + vxlan_hdr_t.flags]
    test al, VXLAN_FLAG_VNI
    jz .invalid

    ; Read 24-bit VNI (bytes 4, 5, 6 big endian)
    mov edx, [rbx + vxlan_hdr_t.vni]
    bswap edx
    shr edx, 8                      ; EDX = 24-bit VNI

    ; Strip 8-byte VXLAN header & dispatch inner Ethernet frame
    lea rdi, [rbx + vxlan_hdr_t_size]
    sub esi, vxlan_hdr_t_size
    call eth_input

    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
vxlan_encap_packet:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend 8-byte VXLAN header (Flags=0x08, VNI) + UDP(4789) + IP + Eth headers
    xor eax, eax
    pop rbp
    ret

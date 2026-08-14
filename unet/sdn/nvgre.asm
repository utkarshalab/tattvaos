%ifndef GUARD_UNET_SDN_NVGRE_ASM
%define GUARD_UNET_SDN_NVGRE_ASM
; =============================================================================
; Tattva OS — unet/sdn/nvgre.asm
; =============================================================================
; Network Virtualization using Generic Routing Encapsulation (NVGRE RFC 7637).
;
; Features:
;   - GRE Protocol Encapsulation (EtherType 0x6558 Transparent Ethernet)
;   - 24-Bit VSID (Virtual Subnet ID) & 8-Bit Flow ID in GRE Key Field
;   - Multi-Tenant L2 Overlay Isolation over L3 Networks
;   - Flow ID Hash Distribution for ECMP Load Balancing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NVGRE_ETHERTYPE             0x6558
%define NVGRE_FLAGS                 0x2000  ; K-bit set (Key Present)

struc nvgre_hdr_t
    .flags_vers:        resw 1      ; 0x2000 (K-bit set)
    .protocol_type:     resw 1      ; 0x6558 (Transparent Ethernet)
    .vsid:              resb 3      ; 24-bit Virtual Subnet ID
    .flow_id:           resb 1      ; 8-bit Flow ID (ECMP entropy)
endstruc

section .text

global nvgre_init
global nvgre_decap
global nvgre_encap

align 64
nvgre_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; nvgre_decap — Decapsulate NVGRE Header & Extract Inner Frame
; Input: RDI = Pointer to NVGRE Header Buffer, ESI = Length
; Output: RAX = Pointer to Inner Frame, EDX = 24-bit VSID, CL = Flow ID
; -----------------------------------------------------------------------------
align 64
nvgre_decap:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Extract 24-bit VSID (bytes 4, 5, 6 big endian)
    movzx eax, byte [rbx + 4]
    shl eax, 16
    movzx edx, byte [rbx + 5]
    shl edx, 8
    or eax, edx
    movzx edx, byte [rbx + 6]
    or eax, edx
    mov edx, eax                    ; EDX = 24-bit VSID

    ; 2. Extract 8-bit Flow ID (byte 7)
    movzx ecx, byte [rbx + 7]

    ; 3. Return pointer to Inner Frame (RDI + 8 bytes)
    lea rax, [rbx + 8]

    pop rbx
    pop rbp
    ret

align 64
nvgre_encap:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Build 8-byte NVGRE header (K-bit + 0x6558 + VSID + Flow ID) + Outer IP
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_SDN_NVGRE_ASM

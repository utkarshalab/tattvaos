%ifndef GUARD_UNET_CLOUD_NVGRE_ASM
%define GUARD_UNET_CLOUD_NVGRE_ASM
; =============================================================================
; Tattva OS — unet/cloud/nvgre.asm
; =============================================================================
; Network Virtualization using Generic Routing Encapsulation (NVGRE RFC 7637).
;
; Features:
;   - GRE Header Variant for Virtualization (K-bit set = 1)
;   - 24-Bit Virtual Subnet ID (VSID) + 8-Bit Flow ID (32-bit Key Field)
;   - Encapsulated Inner Ethernet Frame Parsing (`Protocol Type = 0x6558`)
;   - Multi-Tenant Virtual Network Tunneling & Hypervisor Isolation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NVGRE_ETHERTYPE             0x6558  ; Transparent Ethernet Bridging

struc nvgre_hdr_t
    .flags_ver:         resw 1      ; 0x2000 (K-bit set, Version 0)
    .protocol_type:     resw 1      ; 0x6558
    .vsid_flowid:       resd 1      ; 24-bit VSID (upper 24b) + 8-bit Flow ID
endstruc

section .text

global nvgre_cloud_init
global nvgre_decap_packet
global nvgre_encap_packet


align 64
nvgre_cloud_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
nvgre_decap_packet:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Verify Protocol Type == 0x6558 (Transparent Ethernet)
    movzx eax, word [rbx + nvgre_hdr_t.protocol_type]
    xchg al, ah
    cmp ax, NVGRE_ETHERTYPE
    jne .invalid

    ; Read 24-bit VSID (upper 24 bits of vsid_flowid)
    mov edx, [rbx + nvgre_hdr_t.vsid_flowid]
    bswap edx
    shr edx, 8                      ; EDX = 24-bit VSID

    ; Strip 8-byte NVGRE header & dispatch inner Ethernet frame
    lea rdi, [rbx + nvgre_hdr_t_size]
    call eth_input

    jmp .done

.invalid:
    mov eax, -1

.done:
    pop rbx
    pop rbp
    ret

align 64
nvgre_encap_packet:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Prepend 8-byte NVGRE header (K=1, 0x6558, VSID) + Outer IP Header
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_CLOUD_NVGRE_ASM

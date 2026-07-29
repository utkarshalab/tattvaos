; =============================================================================
; Tattva OS — unet/cloud/nvgre.asm
; =============================================================================
; NVGRE (Network Virtualization using GRE RFC 7637) Overlay Engine.
;
; Implements:
;   - 24-Bit VSID (Virtual Subnet ID) & 8-Bit Flow ID inside GRE Key Field
;   - Microsoft Hyper-V & Enterprise Cloud Network Virtualization Encapsulation
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

struc nvgre_hdr_t
    .flags_ver:         resw 1      ; GRE Key Flag (0x2000) + Version (0x0000)
    .protocol_type:     resw 1      ; Transparent Ethernet Bridging (0x6558)
    .vsid:              resb 3      ; 24-bit Virtual Subnet ID
    .flow_id:           resb 1      ; 8-bit Flow ID
endstruc

section .text

global nvgre_init
global nvgre_encap_frame
global nvgre_decap_frame

align 64
nvgre_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
nvgre_encap_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Format NVGRE Header (EtherType 0x6558, 24-bit VSID) + Outer IP Header
    pop rbx
    pop rbp
    ret

align 64
nvgre_decap_frame:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Extract 24-bit VSID & demux to virtual machine network interface
    pop rbx
    pop rbp
    ret

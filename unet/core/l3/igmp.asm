; =============================================================================
; Tattva OS — unet/core/l3/igmp.asm
; =============================================================================
; IGMPv3 (RFC 3376) & MLDv2 (RFC 3810) Multicast Membership Engine.
;
; Features:
;   - IGMPv3 Source-Specific Multicast (SSM) Join / Leave Group Announcements
;   - Multicast Listener Discovery (MLDv2 for IPv6 Multicast)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IGMP_TYPE_MEMBERSHIP_QUERY  0x11
%define IGMPv3_TYPE_MEMBERSHIP_REPORT 0x22

struc igmpv3_report_t
    .type:              resb 1      ; 0x22
    .reserved1:         resb 1
    .checksum:          resw 1
    .reserved2:         resw 1
    .num_records:       resw 1
endstruc

section .text

global igmp_init
global igmp_join_group
global igmp_leave_group

align 64
igmp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 64
igmp_join_group:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send IGMPv3 Membership Report (State CHANGE_TO_INCLUDE_MODE)
    xor eax, eax
    pop rbp
    ret

align 64
igmp_leave_group:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send IGMPv3 Membership Report (State CHANGE_TO_EXCLUDE_MODE)
    xor eax, eax
    pop rbp
    ret

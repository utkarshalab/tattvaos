%ifndef GUARD_UNET_TOOLS_APP_MULTICAST_ASM
%define GUARD_UNET_TOOLS_APP_MULTICAST_ASM
; =============================================================================
; Tattva OS — unet/tools/app/multicast.asm
; =============================================================================
; Command-Line IP Multicast Sender & Receiver Tool (`mcast`).
;
; Features:
;   - IGMPv3 Join Group (`IP_ADD_MEMBERSHIP`) / Leave Group (`IP_DROP_MEMBERSHIP`)
;   - UDP Multicast Group Ingest & Throughput Metering
;
; Delegates:
;   - IGMP Subsystem                    -> unet/core/l3/igmp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global multicast_main


align 64
multicast_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send IGMPv3 Join Report -> receive UDP multicast stream & count packet rate
    call igmp_join_group
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_MULTICAST_ASM

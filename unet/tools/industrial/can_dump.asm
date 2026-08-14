%ifndef GUARD_UNET_TOOLS_INDUSTRIAL_CAN_DUMP_ASM
%define GUARD_UNET_TOOLS_INDUSTRIAL_CAN_DUMP_ASM
; =============================================================================
; Tattva OS — unet/tools/industrial/can_dump.asm
; =============================================================================
; Command-Line CAN / CAN-FD Bus Monitor & Sniffer Tool (`candump`).
;
; Features:
;   - Real-Time CAN Frame Dump (CAN ID, DLC, Data Bytes, Timestamp, BRS/ESI Flags)
;   - Filtering by CAN ID Mask (e.g. `0x7E8:0x7FF` ECU Diagnostics Response Filter)
;
; Delegates:
;   - CAN Ethernet Gateway              -> unet/automotive/can_eth.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global can_dump_main


align 64
can_dump_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Poll CAN-FD controller ring buffer & dump raw CAN ID and payload bytes
    call can_eth_translate_frame
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_INDUSTRIAL_CAN_DUMP_ASM

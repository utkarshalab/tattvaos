%ifndef GUARD_UNET_TOOLS_IOT_LORAWAN_MON_ASM
%define GUARD_UNET_TOOLS_IOT_LORAWAN_MON_ASM
; =============================================================================
; Tattva OS — unet/tools/iot/lorawan_mon.asm
; =============================================================================
; LoRaWAN Gateway Packet Forwarder Monitor Tool (`lorawan-mon`).
;
; Features:
;   - Semtech UDP Gateway Protocol (PULL_DATA, PUSH_DATA, PULL_RESP, PUSH_ACK)
;   - JSON Payload Metadata Extraction (Frequency, Spreading Factor, RSSI, SNR, Encrypted Payload)
;
; Delegates:
;   - LoRaWAN Protocol Engine           -> unet/wireless/lorawan.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global lorawan_mon_main


align 64
lorawan_mon_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Listen to Semtech UDP gateway port 1700 -> parse PUSH_DATA frames & decrypt FRMPayload
    call lorawan_process_frame
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_IOT_LORAWAN_MON_ASM

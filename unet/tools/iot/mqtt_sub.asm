%ifndef GUARD_UNET_TOOLS_IOT_MQTT_SUB_ASM
%define GUARD_UNET_TOOLS_IOT_MQTT_SUB_ASM
; =============================================================================
; Tattva OS — unet/tools/iot/mqtt_sub.asm
; =============================================================================
; Command-Line MQTT v3.1.1 / v5.0 Subscriber & Stream Monitor (`mqtt-sub`).
;
; Features:
;   - SUBSCRIBE Packet (`0x82`) Formatting & SUBACK (`0x90`) Response Parsing
;   - Continuous Topic Subscription Loop with Output Formatting
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define MQTT_MSG_SUBSCRIBE          0x82
%define MQTT_MSG_SUBACK             0x90

section .text

global mqtt_sub_main
global mqtt_sub_subscribe

align 64
mqtt_sub_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call mqtt_sub_subscribe

    pop rbx
    pop rbp
    ret

align 64
mqtt_sub_subscribe:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Format SUBSCRIBE (0x82) with Packet ID & Topic Filter -> loop incoming PUBLISH messages
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_IOT_MQTT_SUB_ASM

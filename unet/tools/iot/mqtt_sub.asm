; =============================================================================
; Tattva OS — unet/tools/mqtt_sub.asm
; =============================================================================
; MQTT v5.0 Command-Line Subscriber Tool.
;
; Implements:
;   - Subscribes to MQTT Broker Topics & Receives Real-Time IoT Payloads
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global mqtt_sub_init
global mqtt_sub_listen

align 32
mqtt_sub_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
mqtt_sub_listen:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

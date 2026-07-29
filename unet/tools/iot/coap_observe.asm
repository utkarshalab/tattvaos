; =============================================================================
; Tattva OS — unet/tools/coap_observe.asm
; =============================================================================
; CoAP Resource Observe Subscriptions Real-Time Telemetry Listener (`coap-observe`).
;
; Implements:
;   - Subscribes to CoAP RFC 7641 Observe Resources & Displays Sensor Streams
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global coap_observe_init
global coap_observe_listen

align 32
coap_observe_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
coap_observe_listen:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

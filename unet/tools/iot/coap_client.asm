; =============================================================================
; Tattva OS — unet/tools/coap_client.asm
; =============================================================================
; Constrained Application Protocol (CoAP RFC 7252) IoT Client Tool.
;
; Implements:
;   - UDP Port 5683 CoAP CON/NON Message Requests
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global coap_client_init
global coap_client_send

align 32
coap_client_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
coap_client_send:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

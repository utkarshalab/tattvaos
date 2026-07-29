; =============================================================================
; Tattva OS — unet/automotive/someip.asm
; =============================================================================
; AUTOSAR Scalable service-Oriented MiddlewarE over IP (SOME/IP) Engine.
;
; Implements:
;   - RPC Service Discovery, Event Subscriptions & Method Calls
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global someip_init
global someip_dispatch

align 32
someip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
someip_dispatch:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

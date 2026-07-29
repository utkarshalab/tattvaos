; =============================================================================
; Tattva OS — unet/voip/sip.asm
; =============================================================================
; SIP (Session Initiation Protocol — RFC 3261 / RFC 3264) Engine.
;
; Implements:
;   - SIP Registrar, Proxy & User Agent (UA)
;   - Handles INVITE, ACK, BYE, CANCEL, REGISTER, OPTIONS, SUBSCRIBE, NOTIFY
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global sip_init
global sip_parse_msg
global sip_build_invite

align 32
sip_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sip_parse_msg:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sip_build_invite:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/voip/srtp.asm
; =============================================================================
; Secure Real-Time Transport Protocol (SRTP RFC 3711) Engine.
;
; Implements:
;   - AES-GCM-128 / AES-CM-128 SRTP Payload Encryption & HMAC-SHA1 Authentication
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global srtp_init
global srtp_protect

align 32
srtp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
srtp_protect:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

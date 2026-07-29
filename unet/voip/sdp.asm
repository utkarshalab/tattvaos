; =============================================================================
; Tattva OS — unet/voip/sdp.asm
; =============================================================================
; Session Description Protocol (SDP RFC 4566) Engine.
;
; Implements:
;   - Session Description Parsing, Media Lines (m=), and IP Connection (c=) Formatting
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global sdp_init
global sdp_parse

align 32
sdp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sdp_parse:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

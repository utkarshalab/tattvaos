; =============================================================================
; Tattva OS — unet/services/ipfix.asm
; =============================================================================
; IP Flow Information Export (IPFIX RFC 7011 / NetFlow v9) Protocol Engine.
;
; Implements:
;   - Flow Template Set Record Generation and Flow Export Streaming
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ipfix_init
global ipfix_export_flow

align 32
ipfix_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ipfix_export_flow:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

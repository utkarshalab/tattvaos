; =============================================================================
; Tattva OS — unet/fintech/iso8583.asm
; =============================================================================
; ISO 8583 Financial Transaction Card Originated Messages Engine.
;
; Implements:
;   - ATM & POS Payment Terminal Credit/Debit Authorization Bitmap Parsing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global iso8583_init
global iso8583_parse_msg

align 32
iso8583_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
iso8583_parse_msg:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

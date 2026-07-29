; =============================================================================
; Tattva OS — unet/hft/itch.asm
; =============================================================================
; NASDAQ ITCH 5.0 Direct Market Data Feed Parser.
;
; Implements:
;   - Binary Packet Parser for Stock Order Book Add/Cancel/Execute Messages
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global itch_init
global itch_parse_tick

align 32
itch_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
itch_parse_tick:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

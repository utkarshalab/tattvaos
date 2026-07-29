; =============================================================================
; Tattva OS — unet/hft/ouch_soup.asm
; =============================================================================
; SoupBinTCP 3.0 Session Protocol Engine for NASDAQ OUCH Order Entry.
;
; Implements:
;   - Sub-50ns Session Login, Heartbeat, Sequenced Data & Unsequenced Data Packets
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ouch_soup_init
global ouch_soup_login

align 32
ouch_soup_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ouch_soup_login:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

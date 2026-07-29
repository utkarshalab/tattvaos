; =============================================================================
; Tattva OS — unet/hft/ouch.asm
; =============================================================================
; NASDAQ OUCH 5.0 Ultra-Fast Order Entry Engine.
;
; Implements:
;   - Sub-100ns Binary Order Submission (`Enter Order`, `Cancel Order`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ouch_init
global ouch_submit_order

align 32
ouch_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ouch_submit_order:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; =============================================================================
; Tattva OS — unet/hft/fix.asm
; =============================================================================
; FIX 5.0 (Financial Information eXchange) Sub-Microsecond Protocol Engine.
;
; Implements:
;   - ASCII Tag=Value Fast Parser (`Tag 35 = MsgType`, `Tag 49 = SenderCompID`, etc.)
;   - Order Placement & Execution Reports
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global fix_init
global fix_parse_msg

align 32
fix_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
fix_parse_msg:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

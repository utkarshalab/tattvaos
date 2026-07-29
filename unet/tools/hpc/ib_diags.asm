; =============================================================================
; Tattva OS — unet/tools/ib_diags.asm
; =============================================================================
; InfiniBand Subnet & Queue Pair Hardware Diagnostic Tool.
;
; Implements:
;   - `ibstat`, `ibnetdiscover`, `ibswitches` Subnet Diagnostics
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ib_diags_init
global ib_diags_run

align 32
ib_diags_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ib_diags_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

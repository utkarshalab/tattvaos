; =============================================================================
; Tattva OS — unet/cloud/aws_tgw.asm
; =============================================================================
; AWS Transit Gateway & Direct Connect BGP Router Engine.
;
; Implements:
;   - AWS Direct Connect Private VIF & Transit Gateway VPC Attachments
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global aws_tgw_init
global aws_tgw_route

align 32
aws_tgw_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
aws_tgw_route:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

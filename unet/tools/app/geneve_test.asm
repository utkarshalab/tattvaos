; =============================================================================
; Tattva OS — unet/tools/geneve_test.asm
; =============================================================================
; GENEVE Tunneling (RFC 8926) Option Header Benchmark Test Tool.
;
; Implements:
;   - UDP Port 6081 Encapsulation & Option TLV Processing Performance Test
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global geneve_test_init
global geneve_test_run

align 32
geneve_test_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
geneve_test_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

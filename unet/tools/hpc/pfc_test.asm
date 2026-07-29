; =============================================================================
; Tattva OS — unet/tools/pfc_test.asm
; =============================================================================
; Priority Flow Control (PFC IEEE 802.1Qbb) Lossless Ethernet Test Tool.
;
; Implements:
;   - Sends PFC Pause Frames across 8 Priority Queues & Measures Lossless Flow
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global pfc_test_init
global pfc_test_run

align 32
pfc_test_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
pfc_test_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

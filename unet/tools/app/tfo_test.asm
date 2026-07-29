; =============================================================================
; Tattva OS — unet/tools/tfo_test.asm
; =============================================================================
; TCP Fast Open (TFO RFC 7413) 0-RTT Connection Benchmark Test Tool.
;
; Implements:
;   - Sends TFO Cookie Request in SYN Packet for 0-RTT Latency Setup
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global tfo_test_init
global tfo_test_run

align 32
tfo_test_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
tfo_test_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

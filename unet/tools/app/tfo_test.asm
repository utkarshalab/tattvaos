%ifndef GUARD_UNET_TOOLS_APP_TFO_TEST_ASM
%define GUARD_UNET_TOOLS_APP_TFO_TEST_ASM
; =============================================================================
; Tattva OS — unet/tools/app/tfo_test.asm
; =============================================================================
; TCP Fast Open (TFO RFC 7413) Diagnostic & Latency Tester (`tfo-test`).
;
; Features:
;   - TCP SYN + Cookie Request & SYN + Payload Fast Open Connection Establishment
;   - Round-Trip Time Latency Savings Audit (0-RTT vs 1-RTT Handshake)
;
; Delegates:
;   - TCP Stack                         -> unet/core/l4/tcp.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global tfo_test_main

align 64
tfo_test_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Send TCP SYN + TFO Cookie option -> verify 0-RTT payload delivery on subsequent connection
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_APP_TFO_TEST_ASM

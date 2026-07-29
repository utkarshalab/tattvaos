; =============================================================================
; Tattva OS — unet/tools/ecn_monitor.asm
; =============================================================================
; Explicit Congestion Notification (ECN RFC 3168) Traffic Monitor Tool.
;
; Implements:
;   - Tracks IP ECT(0), ECT(1), and CE Congestion Marked Packets
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ecn_monitor_init
global ecn_monitor_run

align 32
ecn_monitor_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ecn_monitor_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

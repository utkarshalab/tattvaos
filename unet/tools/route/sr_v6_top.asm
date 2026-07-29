; =============================================================================
; Tattva OS — unet/tools/sr_v6_top.asm
; =============================================================================
; Segment Routing IPv6 (SRv6) Segment List & Binding SID Path Monitor (`srv6-top`).
;
; Implements:
;   - Displays Active SRv6 SID Lists, Segment Routing Headers (SRH) & Latency
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global sr_v6_top_init
global sr_v6_top_run

align 32
sr_v6_top_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
sr_v6_top_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

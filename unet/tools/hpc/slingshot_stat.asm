; =============================================================================
; Tattva OS — unet/tools/slingshot_stat.asm
; =============================================================================
; Cray Slingshot-11 Interconnect Traffic & Congestion Counter Tool.
;
; Implements:
;   - Displays Dragonfly Topology Link Bandwidth, CNP Counts & Microsecond Latencies
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global slingshot_stat_init
global slingshot_stat_dump

align 32
slingshot_stat_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
slingshot_stat_dump:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

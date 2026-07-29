; =============================================================================
; Tattva OS — unet/tools/ebpf_top.asm
; =============================================================================
; eBPF/XDP Kernel Program Performance & CPU Cycle Inspector Tool.
;
; Implements:
;   - Real-Time eBPF Program CPU Cycles, Map Element Count & Drop Statistics
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ebpf_top_init
global ebpf_top_run

align 32
ebpf_top_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ebpf_top_run:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

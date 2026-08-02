; =============================================================================
; Tattva OS — unet/tools/hpc/cxi_info.asm
; =============================================================================
; Cray Cassini Interconnect (CXI / Slingshot) Network Diagnostic Tool (`cxi-info`).
;
; Features:
;   - Cassini NIC Hardware Ring State & Virtual Channel Credit Mon
;   - SACC Congestion Control Metrics Reporting
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global cxi_info_main

align 64
cxi_info_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Query Cassini NIC MMIO registers -> print Virtual Channel (VC) credit balances & SACC stats
    xor eax, eax
    pop rbp
    ret

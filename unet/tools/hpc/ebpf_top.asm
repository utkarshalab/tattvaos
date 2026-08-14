%ifndef GUARD_UNET_TOOLS_HPC_EBPF_TOP_ASM
%define GUARD_UNET_TOOLS_HPC_EBPF_TOP_ASM
; =============================================================================
; Tattva OS — unet/tools/hpc/ebpf_top.asm
; =============================================================================
; Real-Time In-Kernel eBPF Program & Map Performance Top Monitor (`ebpftop`).
;
; Features:
;   - Real-Time eBPF Program Execution Frequency (Runs/Sec) & Average CPU Run Time (ns)
;   - BPF Map Memory Allocation & Lookups/Sec Reporting
;
; Delegates:
;   - eBPF Engine                       -> unet/ebpf/ebpf.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ebpf_top_main


align 64
ebpf_top_main:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Monitor active eBPF programs, XDP actions (PASS/DROP/REDIRECT), and CPU run times
    call ebpf_exec_bytecode
    pop rbp
    ret

%endif ; GUARD_UNET_TOOLS_HPC_EBPF_TOP_ASM

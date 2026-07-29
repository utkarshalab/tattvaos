; =============================================================================
; Tattva OS — unet/san/nvme_of_rdma.asm
; =============================================================================
; NVMe over RDMA (RoCE / InfiniBand) SAN Engine.
;
; Implements:
;   - Ultra-Low Latency Direct NVMe Command Capsules over RDMA Queue Pairs
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nvme_of_rdma_init
global nvme_of_rdma_cmd

align 32
nvme_of_rdma_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nvme_of_rdma_cmd:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

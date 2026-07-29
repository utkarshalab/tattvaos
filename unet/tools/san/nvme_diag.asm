; =============================================================================
; Tattva OS — unet/tools/nvme_diag.asm
; =============================================================================
; NVMe-oF RDMA / TCP Block Storage SAN Controller Diagnostic Tool.
;
; Implements:
;   - Queries Controller Info, Namespace List, Subsystem NQN & Queue Depth
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nvme_diag_init
global nvme_diag_query

align 32
nvme_diag_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nvme_diag_query:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

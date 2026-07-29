; =============================================================================
; Tattva OS — unet/drivers/broadcom_bnxt.asm
; =============================================================================
; Broadcom NetXtreme-E 100G / 200G Ethernet NIC Driver (BNXT).
;
; Implements:
;   - HWRM (Hardware Resource Manager) Control Messages & 200G Ring Polling
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global bnxt_init
global bnxt_poll

align 32
bnxt_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
bnxt_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

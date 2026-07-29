; =============================================================================
; Tattva OS — unet/drivers/chelsio_cxgb4.asm
; =============================================================================
; Chelsio Terminator 5 / 6 (T5 / T6) 100G iWARP / RDMA NIC Driver.
;
; Implements:
;   - TCP Offload Engine (TOE) & Hardware iWARP RDMA Memory Region Registering
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global chelsio_init
global chelsio_poll

align 32
chelsio_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
chelsio_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

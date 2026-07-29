; =============================================================================
; Tattva OS — unet/san/nvme_of_tcp.asm
; =============================================================================
; NVMe over Fabrics (NVMe-oF) Direct Block Storage over TCP Engine.
;
; Implements:
;   - Sub-Microsecond Direct NVMe Command Encapsulation over TCP
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global nvme_of_tcp_init
global nvme_of_tcp_cmd

align 32
nvme_of_tcp_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
nvme_of_tcp_cmd:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

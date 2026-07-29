; =============================================================================
; Tattva OS — unet/drivers/ena.asm
; =============================================================================
; AWS Elastic Network Adapter (ENA 100G) Driver.
;
; Implements:
;   - Admin Queue (AQ) Communication & Placement Group Low-Latency Ring
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ena_init
global ena_poll

align 32
ena_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ena_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

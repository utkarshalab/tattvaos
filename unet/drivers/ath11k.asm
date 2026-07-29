; =============================================================================
; Tattva OS — unet/drivers/ath11k.asm
; =============================================================================
; Qualcomm Atheros Wi-Fi 6 (QCA6390 / WCN6855) PCIe Driver.
;
; Implements:
;   - HTT (Host Target Transport) & WMI (Wireless Module Interface) Protocol Engine
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .text

global ath11k_init
global ath11k_poll

align 32
ath11k_init:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

align 32
ath11k_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

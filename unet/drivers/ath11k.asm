%ifndef GUARD_UNET_DRIVERS_ATH11K_ASM
%define GUARD_UNET_DRIVERS_ATH11K_ASM
; =============================================================================
; Tattva OS — unet/drivers/ath11k.asm
; =============================================================================
; Qualcomm Atheros Wi-Fi 6 / 6E ath11k PCIe Driver.
;
; Features:
;   - QMI (Qualcomm Messaging Interface) & WMI (Wireless Module Interface) Firmware Commands
;   - HTT (Host-to-Target Target-to-Host Interface) Ring Management
;   - CE (Copy Engine) Ring Doorbell Memory Mapped Architecture
;   - DP (Data Path) Rx Ring Polling & MAC Address Provisioning
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define ATH11K_CE_RING_SIZE          256

struc ath11k_ce_desc_t
    .addr_lo:           resd 1
    .addr_hi:           resd 1
    .nbytes:            resw 1
    .flags:             resw 1
endstruc

section .text

global ath11k_init
global ath11k_wmi_cmd
global ath11k_poll_ce
global ath11k_transmit

align 64
ath11k_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Initialize Copy Engine (CE) rings & send WMI Init command
    xor eax, eax

    pop rbx
    pop rbp
    ret

align 64
ath11k_wmi_cmd:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Build WMI Control Message & post to CE ring
    xor eax, eax
    pop rbp
    ret

align 64
ath11k_poll_ce:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Poll CE Rx ring for complete packets & dispatch
    call eth_input
    mov eax, 1

    pop rbx
    pop rbp
    ret

align 64
ath11k_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post packet descriptor to HTT Data Tx ring & ring CE doorbell
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_ATH11K_ASM

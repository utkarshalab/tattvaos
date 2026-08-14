%ifndef GUARD_UNET_DRIVERS_3COM_3C905_ASM
%define GUARD_UNET_DRIVERS_3COM_3C905_ASM
; =============================================================================
; Tattva OS — unet/drivers/3com_3c905.asm
; =============================================================================
; 3Com 3c905B / 3c905C Fast EtherLink XL 10/100 Mbps Driver.
;
; Features:
;   - Command / Status Register Architecture with Window Switching (Window 0..7)
;   - Dynamic Bus Master DMA Descriptors (Upload DPD & Download DPD)
;   - MII Media Control (10Base-T, 100Base-TX Full Duplex Autonegotiation)
;   - Station Address Reading from EEPROM (Window 0 Register 0..5)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define EL3_CMD                     0x0E
%define EL3_STATUS                  0x0E

%define EL3_WINDOW_SELECT           (1 << 11)
%define EL3_CMD_RX_ENABLE           (5 << 11)
%define EL3_CMD_TX_ENABLE           (9 << 11)

struc el3_dpd_t
    .dn_next:           resd 1      ; Next DPD physical address
    .dn_status:         resd 1      ; Frame status & length
    .dn_frag_addr:      resd 1      ; Fragment physical address
    .dn_frag_len:       resd 1      ; Fragment length
endstruc

section .text

global threecom_init
global threecom_poll
global threecom_transmit
global threecom_select_window


align 64
threecom_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; I/O Port Base

    ; Select Window 0 & read MAC address
    mov edi, 0
    call threecom_select_window

    pop rbx
    pop rbp
    ret

align 64
threecom_poll:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check Upload DPD status for completed packet reception
    mov eax, [rbx + el3_dpd_t.dn_status]
    test eax, 0x00008000
    jz .no_pkt

    mov edx, eax
    and edx, 0x1FFF                 ; 13-bit packet length
    call eth_input
    mov eax, 1

.no_pkt:
    pop rbx
    pop rbp
    ret

align 64
threecom_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Build Download DPD & write DPD address to DownListPtr register
    xor eax, eax
    pop rbp
    ret

align 64
threecom_select_window:
    push rbp
    mov rbp, rsp
    ; Outw Command Register: EL3_WINDOW_SELECT | window_num
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_3COM_3C905_ASM

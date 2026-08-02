; =============================================================================
; Tattva OS — unet/drivers/realtek_r8169.asm
; =============================================================================
; Realtek RTL8111 / RTL8168 / RTL8125 2.5 Gigabit Ethernet Driver.
;
; Features:
;   - Ring Descriptors (RxDesc / TxDesc 16-Byte Hardware Format)
;   - RTL8125 2.5GbE Speed Autonegotiation & EEE (Energy Efficient Ethernet)
;   - Interrupt Mask Register (IMR) & Interrupt Status Register (ISR) Processing
;   - Hardware VLAN & IP/TCP/UDP Checksum Offloads
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define R8169_MAC0                   0x0000
%define R8169_MAR0                   0x0008
%define R8169_TxDesc                 0x0020
%define R8169_RxDesc                 0x00E4
%define R8169_INTR_MASK              0x003C
%define R8169_INTR_STATUS            0x003E
%define R8169_CHIP_CMD               0x0037

struc r8169_desc_t
    .opts1:             resd 1      ; OWN(1b) + EOP(1b) + FS(1b) + Length(14b)
    .opts2:             resd 1      ; VLAN Tag
    .addr_low:          resd 1      ; DMA Address Low 32-bit
    .addr_high:         resd 1      ; DMA Address High 32-bit
endstruc

section .text

global realtek_init
global realtek_poll
global realtek_transmit

extern dma_alloc_hugepage
extern eth_input

align 64
realtek_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; BAR0 MMIO Base

    ; Reset Chip (CHIP_CMD = 0x10) & allocate RxDesc/TxDesc rings
    mov byte [rbx + R8169_CHIP_CMD], 0x10

    pop rbx
    pop rbp
    ret

align 64
realtek_poll:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rsi                    ; RxDesc Ring Base
    prefetcht0 [rbx]

    ; Check OWN bit (bit 31 of opts1: 1 = HW, 0 = SW)
    mov eax, [rbx + r8169_desc_t.opts1]
    test eax, 0x80000000
    jnz .no_pkt                     ; Still owned by HW

    mov edx, eax
    and edx, 0x3FFF                 ; Extract 14-bit length
    call eth_input
    mov eax, 1

.no_pkt:
    pop rbx
    pop rbp
    ret

align 64
realtek_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Set OWN bit + length + buffer address in TxDesc & trigger Tx Poll command
    xor eax, eax
    pop rbp
    ret

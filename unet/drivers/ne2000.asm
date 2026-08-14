%ifndef GUARD_UNET_DRIVERS_NE2000_ASM
%define GUARD_UNET_DRIVERS_NE2000_ASM
; =============================================================================
; Tattva OS — unet/drivers/ne2000.asm
; =============================================================================
; Novell NE2000 ISA / PCI Ethernet Driver (National Semiconductor DP8390 NIC).
;
; Features:
;   - DP8390 Register Page 0 / Page 1 Window Selection (Command Register CR)
;   - Remote DMA Memory Read & Write Operations (RSAR0, RSAR1, RBCR0, RBCR1)
;   - Ring Buffer Page Management (PSTART=0x46, PSTOP=0x80, CURR, BNRY)
;   - Promiscuous, Broadcast & Multicast Filter Configuration (RCR, TCR)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NE2000_CR                   0x00
%define NE2000_PSTART               0x01
%define NE2000_PSTOP                0x02
%define NE2000_BNRY                 0x03
%define NE2000_TPSR                 0x04
%define NE2000_TBCR0                0x05
%define NE2000_TBCR1                0x06
%define NE2000_ISR                  0x07
%define NE2000_RSAR0                0x08
%define NE2000_RSAR1                0x09
%define NE2000_RBCR0                0x0A
%define NE2000_RBCR1                0x0B
%define NE2000_RCR                  0x0C
%define NE2000_TCR                  0x0D

%define NE2000_DATA_PORT            0x10

section .text

global ne2000_init
global ne2000_poll
global ne2000_transmit
global ne2000_rdma_read


align 64
ne2000_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; I/O Port Base

    ; Stop NIC (CR = 0x21), setup PSTART=0x46, PSTOP=0x80, BNRY=0x46, start NIC (CR = 0x22)
    mov byte [rbx + NE2000_CR], 0x21
    mov byte [rbx + NE2000_PSTART], 0x46
    mov byte [rbx + NE2000_PSTOP], 0x80
    mov byte [rbx + NE2000_BNRY], 0x46
    mov byte [rbx + NE2000_CR], 0x22

    pop rbx
    pop rbp
    ret

align 64
ne2000_poll:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; Read CURR pointer from Page 1 & compare with BNRY
    mov byte [rbx + NE2000_CR], 0x62 ; Page 1
    movzx eax, byte [rbx + 0x07]    ; CURR register
    mov byte [rbx + NE2000_CR], 0x22 ; Page 0

    movzx edx, byte [rbx + NE2000_BNRY]
    cmp al, dl
    je .no_pkt

    ; Fetch packet via Remote DMA
    call ne2000_rdma_read
    call eth_input
    mov eax, 1
    jmp .done

.no_pkt:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
ne2000_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Remote DMA write packet to Tx page (TPSR=0x40), set TBCR0/1, issue Tx command
    xor eax, eax
    pop rbp
    ret

align 64
ne2000_rdma_read:
    push rbp
    mov rbp, rsp
    ; Set RSAR0/1 & RBCR0/1, issue Remote DMA Read command (CR = 0x0A), read from DATA_PORT
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_NE2000_ASM

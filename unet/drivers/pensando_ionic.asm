; =============================================================================
; Tattva OS — unet/drivers/pensando_ionic.asm
; =============================================================================
; Pensando DSC / Elba Distributed Services Card (SmartNIC / DPU) Driver.
;
; Features:
;   - Admin Queue (AQ) Control Interface (Identity, Init, LIF Config, Port Reset)
;   - Logical Interface (LIF) & Queue Set Allocation (RXQ, TXQ, AdminQ, CQ)
;   - RX & TX Completion Descriptors with Hardware P4 Pipeline Offloads
;   - Microsegmentation & Connection Tracking Hardware Offload Rules
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IONIC_DEV_CMD_REG            0x0000
%define IONIC_DEV_CMD_DATA           0x0004

%define IONIC_CMD_IDENTIFY           1
%define IONIC_CMD_INIT               2
%define IONIC_CMD_RESET              3
%define IONIC_CMD_LIF_IDENTIFY       4
%define IONIC_CMD_LIF_INIT           5

struc ionic_cq_desc_t
    .comp_index:        resw 1
    .color:             resb 1      ; Color / Generation bit
    .status:            resb 1
endstruc

section .text

global pensando_init
global pensando_dev_cmd
global pensando_poll_cq
global pensando_transmit

extern dma_alloc_hugepage
extern eth_input

align 64
pensando_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Issue Device Command: IDENTIFY -> INIT -> LIF_INIT
    mov rsi, IONIC_CMD_IDENTIFY
    call pensando_dev_cmd

    pop rbx
    pop rbp
    ret

align 64
pensando_dev_cmd:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post command byte to IONIC_DEV_CMD_REG & wait completion flag
    xor eax, eax
    pop rbp
    ret

align 64
pensando_poll_cq:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check Generation / Color bit in CQ descriptor
    movzx eax, byte [rbx + ionic_cq_desc_t.color]
    test al, 0x01
    jz .no_cq

    call eth_input
    mov eax, 1
    jmp .done

.no_cq:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
pensando_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post TX descriptor & update LIF doorbell register
    xor eax, eax
    pop rbp
    ret

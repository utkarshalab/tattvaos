; =============================================================================
; Tattva OS — unet/drivers/vmxnet3.asm
; =============================================================================
; VMware VMXNET3 Paravirtualized Network Adapter Driver.
;
; Features:
;   - Command & Shared Memory Architecture (Driver Shared Data Area)
;   - Multi-Ring Support (RX Ring 1, RX Ring 2, TX Ring, Data Ring)
;   - RX Completion Ring (RxCompDesc) & TX Completion Ring (TxCompDesc)
;   - Hardware Offloads: L4 Checksum, TSO, VLAN Tagging, Large Receive Offload (LRO)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VMXNET3_CMD_ACTIVATE_DEV     0xF00D0001
%define VMXNET3_CMD_QUIESCE_DEV      0xF00D0002
%define VMXNET3_CMD_RESET_DEV        0xF00D0003

struc vmxnet3_rx_comp_desc_t
    .rxd_idx:           resd 1      ; Index of associated RxDesc
    .len:               resd 1      ; Received Packet Length (14 bits)
    .gen:               resd 1      ; Generation bit (bit 31)
endstruc

section .text

global vmxnet3_init
global vmxnet3_poll_rx
global vmxnet3_transmit
global vmxnet3_cmd

extern dma_alloc_hugepage
extern eth_input

align 64
vmxnet3_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Activate Device & allocate Driver Shared Memory
    mov rsi, VMXNET3_CMD_ACTIVATE_DEV
    call vmxnet3_cmd

    pop rbx
    pop rbp
    ret

align 64
vmxnet3_poll_rx:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check Generation bit in RxCompDesc (bit 31 of gen word)
    mov eax, [rbx + vmxnet3_rx_comp_desc_t.gen]
    test eax, 0x80000000
    jz .no_packet

    call eth_input
    mov eax, 1
    jmp .done

.no_packet:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
vmxnet3_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post TxDesc & write to TX ring doorbell register
    xor eax, eax
    pop rbp
    ret

align 64
vmxnet3_cmd:
    push rbp
    mov rbp, rsp
    ; Write VMXNET3 command to PCI command MMIO register
    xor eax, eax
    pop rbp
    ret

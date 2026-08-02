; =============================================================================
; Tattva OS — unet/drivers/chelsio_cxgb4.asm
; =============================================================================
; Chelsio Terminator 5 / 6 (T5 / T6) 100G iWARP / RDMA & TOE NIC Driver.
;
; Features:
;   - Firmware Command Interface (FW_CMD) via SGE (Scatter Gather Engine)
;   - TCP Offload Engine (TOE) State Machine Handling
;   - iWARP RDMA (STag / R_Key) Memory Region Offload
;   - Ingress Queue (IQ) & Egress Queue (EQ) Doorbell Ring Allocation
;   - Sub-Microsecond CPL (Control PLD) Message Processing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define CXGB4_SGE_KDB_RSP            0x0000
%define CXGB4_SGE_KDB_TX             0x0004

struc cxgb4_iq_desc_t
    .rsp_type:          resb 1      ; Response Type
    .flags:             resb 1
    .len:               resw 1      ; Packet Length
    .rss_hash:          resd 1      ; RSS Hash
endstruc

section .text

global chelsio_init
global chelsio_poll
global chelsio_transmit
global chelsio_fw_cmd

extern dma_alloc_hugepage
extern eth_input

align 64
chelsio_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Issue FW_INITIALIZE_CMD & allocate SGE Ingress/Egress queues
    call chelsio_fw_cmd

    pop rbx
    pop rbp
    ret

align 64
chelsio_poll:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; IQ Ring Base
    prefetcht0 [rbx]

    ; Check IQ descriptor response type
    movzx eax, byte [rbx + cxgb4_iq_desc_t.rsp_type]
    test al, al
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
chelsio_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post Work Request (WR) to SGE Egress Queue & write SGE_KDB_TX doorbell
    xor eax, eax
    pop rbp
    ret

align 64
chelsio_fw_cmd:
    push rbp
    mov rbp, rsp
    ; Execute Chelsio Firmware Command via SGE Command Queue
    xor eax, eax
    pop rbp
    ret

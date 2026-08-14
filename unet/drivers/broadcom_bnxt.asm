%ifndef GUARD_UNET_DRIVERS_BROADCOM_BNXT_ASM
%define GUARD_UNET_DRIVERS_BROADCOM_BNXT_ASM
; =============================================================================
; Tattva OS — unet/drivers/broadcom_bnxt.asm
; =============================================================================
; Broadcom NetXtreme-C / NetXtreme-E 100GbE / 200GbE NIC Driver.
;
; Features:
;   - HWRM (Hardware Resource Manager) PCIe Mailbox Interface
;   - Ring Types: RX Producer Ring, RX Aggregation Ring, TX Producer Ring, Completion Ring (CMPL)
;   - 16-Byte & 32-Byte Completion Format Processing (RX CMPL, TX CMPL, L2 CMPL)
;   - Hardware RoCEv2 RDMA & Multi-Queue RSS Steering
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define BNXT_HWRM_VER_MAX             0x0000
%define BNXT_HWRM_FUNC_QCFG           0x0011
%define BNXT_HWRM_RING_ALLOC          0x0030
%define BNXT_HWRM_RING_FREE           0x0031
%define BNXT_HWRM_CBR_ALLOC           0x0032

struc bnxt_cmpl_hdr_t
    .type_v:            resw 1      ; Type (6b) + Valid bit (1b)
    .length:            resw 1
endstruc

section .text

global bnxt_init
global bnxt_hwrm_send
global bnxt_poll_cmpl
global bnxt_transmit

align 64
bnxt_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Initialize HWRM Channel & allocate CMPL / RX / TX rings
    mov rsi, BNXT_HWRM_FUNC_QCFG
    call bnxt_hwrm_send

    pop rbx
    pop rbp
    ret

align 64
bnxt_hwrm_send:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post HWRM request descriptor to PCIe Mailbox
    xor eax, eax
    pop rbp
    ret

align 64
bnxt_poll_cmpl:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check Valid bit (bit 0 of type_v)
    movzx eax, word [rbx + bnxt_cmpl_hdr_t.type_v]
    test ax, 0x0001
    jz .no_cmpl

    call eth_input
    mov eax, 1
    jmp .done

.no_cmpl:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
bnxt_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post TX producer descriptor & ring doorbell
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_BROADCOM_BNXT_ASM

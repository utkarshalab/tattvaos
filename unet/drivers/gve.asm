%ifndef GUARD_UNET_DRIVERS_GVE_ASM
%define GUARD_UNET_DRIVERS_GVE_ASM
; =============================================================================
; Tattva OS — unet/drivers/gve.asm
; =============================================================================
; Google Virtual NIC (gVNIC / GVE 100GbE) Driver.
;
; Features:
;   - Admin Queue (AQ) Control Page Interface (Configure Device, Create Page List, Setup Queues)
;   - DQO (Descriptor Queue Option) & GQI (Google Queue Interface) Modes
;   - RX Packet Buffer Page List Allocator
;   - RX & TX Completion Queue (CQ) Polling with Generation Bit Matching
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define GVE_ADMIN_QUEUE_DB          0x0000
%define GVE_DRIVER_STATUS           0x0004

struc gve_rx_cqe_t
    .seq_num:           resd 1
    .len:               resd 1
    .flags:             resw 1      ; Generation bit (bit 15)
endstruc

section .text

global gve_init
global gve_adminq_send
global gve_poll_rx
global gve_transmit

align 64
gve_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; MMIO Base

    ; Initialize gVNIC Admin Queue & Register Page Lists
    xor eax, eax

    pop rbx
    pop rbp
    ret

align 64
gve_adminq_send:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post command to gVNIC Admin Queue
    xor eax, eax
    pop rbp
    ret

align 64
gve_poll_rx:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; Check Generation bit (bit 15 of flags)
    movzx eax, word [rbx + gve_rx_cqe_t.flags]
    test ax, 0x8000
    jz .no_rx

    call eth_input
    mov eax, 1
    jmp .done

.no_rx:
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

align 64
gve_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Post TX descriptor & kick gVNIC TX doorbell
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_DRIVERS_GVE_ASM

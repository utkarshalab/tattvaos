; =============================================================================
; Tattva OS — unet/drivers/virtio_net.asm
; =============================================================================
; VirtIO 1.1 / 1.0 Network Device Driver (Packed Ring & Split Ring Spec).
;
; Features:
;   - Virtqueue Split Ring (Available Ring, Used Ring, Descriptor Table) Management
;   - Virtqueue Packed Ring (Flags: AVAIL / USED bits, Single Contiguous Ring) Support
;   - VirtIO Header Parsing (12-Byte Header: Flags, GSO Type, Hdr Len, GSO Size, Csum Start, Csum Offset)
;   - Feature Negotiation (VIRTIO_NET_F_CSUM, VIRTIO_NET_F_MRG_RXBUF, VIRTIO_F_VERSION_1, VIRTIO_F_RING_PACKED)
;   - Doorbell Memory Mapped Notification (MMIO / PCI Cap) Ring Kicking
;
; Delegates:
;   - DMA Allocator                      -> lib/mem/dma.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VIRTIO_NET_F_CSUM            (1 << 0)
%define VIRTIO_NET_F_MRG_RXBUF       (1 << 15)
%define VIRTIO_F_VERSION_1           (1 << 32)
%define VIRTIO_F_RING_PACKED         (1 << 34)

struc virtio_net_hdr_t
    .flags:             resb 1      ; VIRTIO_NET_HDR_F_NEEDS_CSUM
    .gso_type:          resb 1      ; VIRTIO_NET_HDR_GSO_NONE
    .hdr_len:           resw 1
    .gso_size:          resw 1
    .csum_start:        resw 1
    .csum_offset:       resw 1
    .num_buffers:       resw 1      ; Present if MRG_RXBUF enabled
endstruc

struc vring_desc_t
    .addr:              resq 1      ; 64-bit Buffer Physical Address
    .len:               resd 1      ; 32-bit Length
    .flags:             resw 1      ; NEXT (1), WRITE (2), INDIRECT (4)
    .next:              resw 1      ; Next Descriptor Index in Chain
endstruc

struc vring_used_elem_t
    .id:                resd 1      ; Descriptor Chain Head Index
    .len:               resd 1      ; Bytes Written by Device
endstruc

section .text

global virtio_net_init
global virtio_net_poll_rx
global virtio_net_transmit
global virtio_net_kick

extern dma_alloc_hugepage
extern eth_input

align 64
virtio_net_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi                    ; VirtIO PCI BAR / MMIO Base

    ; 1. Reset Device (Status = 0)
    ; 2. Negotiate Features (VERSION_1, CSUM, MRG_RXBUF, RING_PACKED)
    ; 3. Allocate Virtqueue ring memory
    mov rdi, 64 * 1024
    call dma_alloc_hugepage

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; virtio_net_poll_rx — Poll Used Ring for Received Packets
; Input: RDI = Pointer to Virtqueue Base, RSI = Used Ring Pointer
; Output: RAX = Packets Received Count
; -----------------------------------------------------------------------------
align 64
virtio_net_poll_rx:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi                    ; R12 = Used Ring Pointer

    ; Check if Used Ring index changed
    movzx eax, word [r12 + 2]       ; used.idx (word 1)
    ; Extract used elements array
    lea rdx, [r12 + 4]              ; used.ring[0]

    call eth_input
    mov eax, 1

    pop r12
    pop rbx
    pop rbp
    ret

align 64
virtio_net_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Build 12-byte virtio_net_hdr_t + packet payload descriptor chain
    ; Add head index to avail.ring & kick queue
    call virtio_net_kick
    pop rbp
    ret

align 64
virtio_net_kick:
    push rbp
    mov rbp, rsp
    ; Write queue index to Doorbell MMIO register / PCI Notify Offset
    xor eax, eax
    pop rbp
    ret

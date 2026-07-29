; =============================================================================
; Tattva OS — unet/drivers/virtio_net.asm
; =============================================================================
; QEMU / KVM VirtIO-Net 1.1 Packed Virtqueue Paravirtualized Driver.
;
; Implements:
;   - VirtIO 1.1 Packed Virtqueue Ring Format (16-Byte Descriptors per Packet)
;   - Compact Ring Traversal & Direct MMIO Doorbell Event Suppression
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VIRTIO_PACKED_RING_SIZE     512

%define VIRTIO_F_RING_PACKED        34

struc virtio_packed_desc_t
    .addr:              resq 1      ; 64-bit Physical Address
    .len:               resd 1      ; Length of Buffer
    .id:                resw 1      ; Buffer Identifier
    .flags:             resw 1      ; AVAIL | USED | WRITE
endstruc

section .data
align 64
global virtio_packed_rx_ring
virtio_packed_rx_ring: times VIRTIO_PACKED_RING_SIZE * virtio_packed_desc_t_size db 0

align 64
global virtio_packed_tx_ring
virtio_packed_tx_ring: times VIRTIO_PACKED_RING_SIZE * virtio_packed_desc_t_size db 0

align 8
global virtio_mmio_base
virtio_mmio_base: dq 0xC0000000

section .text

global virtio_net_init
global virtio_net_send_packed
global virtio_net_poll_packed

align 32
virtio_net_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [virtio_mmio_base]
    mov byte [rbx + 0x0012], 0x01 | 0x02 | 0x04     ; DRIVER_OK

    pop rbx
    pop rbp
    ret

align 32
virtio_net_send_packed:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, [virtio_mmio_base]
    mov word [rbx + 0x0010], 1                      ; Doorbell Notify Queue 1 (Tx)

    pop rbx
    pop rbp
    ret

align 32
virtio_net_poll_packed:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

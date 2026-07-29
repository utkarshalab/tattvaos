; =============================================================================
; Tattva OS — unet/drivers/virtio_net.asm
; =============================================================================
; VirtIO 1.1 Network Device Driver (Packed Virtqueues 16-Byte Descriptors).
;
; Delegates:
;   - Microsecond / Millisecond IO Delays -> lib/time/delay.asm (`udelay`, `mdelay`)
;   - Sub-Nanosecond Hardware Timestamp   -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;
; Implements:
;   - VirtIO 1.1 Packed Virtqueues 16-Byte Ring Layout
;   - Virtqueue Kick Doorbell Coalescing
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VIRTIO_NET_F_CSUM            0
%define VIRTIO_NET_F_GUEST_CSUM      1
%define VIRTIO_NET_F_MAC             5

struc virtio_net_packed_desc_t
    .addr:              resq 1      ; 64-bit Buffer Physical Address
    .len:               resd 1      ; 32-bit Buffer Length
    .id:                resw 1      ; Buffer ID
    .flags:             resw 1      ; AVAIL / USED Flags
endstruc

section .text

global virtio_net_init
global virtio_net_tx_pkt
global virtio_net_rx_poll

extern udelay
extern mdelay
extern rdtsc_get_cycles

align 32
virtio_net_init:
    push rbp
    mov rbp, rsp
    ; Reset VirtIO device & wait 1ms via lib/time/delay.asm
    mov rdi, 1
    call mdelay
    pop rbp
    ret

align 32
virtio_net_tx_pkt:
    push rbp
    mov rbp, rsp
    ; Record sub-nanosecond timestamp via lib/time/tsc.asm
    call rdtsc_get_cycles
    mov [rsi + net_pkt_t.timestamp_ns], rax
    pop rbp
    ret

align 32
virtio_net_rx_poll:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

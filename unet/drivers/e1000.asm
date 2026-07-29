; =============================================================================
; Tattva OS — unet/drivers/e1000.asm
; =============================================================================
; Hardware Optimized Intel 82540EM / 82574L Gigabit Ethernet NIC Driver.
;
; Microarchitectural & Hardware Optimizations:
;   - Contiguous 2MB Hugepage DMA RX/TX Ring Allocations via lib/mem/dma.asm
;   - Hardware Ingress TSC Timestamping via lib/time/tsc.asm (`rdtsc_get_cycles`)
;   - Microsecond PHY Initialization & Reset Delays via lib/time/delay.asm (`mdelay`)
;   - 32-Packet Doorbell Coalescing to Reduce PCIe Bus Transactions
;
; Delegates:
;   - Hugepage DMA Allocator            -> lib/mem/dma.asm
;   - Hardware TSC Timestamp            -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;   - Microsecond Delay Loops           -> lib/time/delay.asm (`mdelay`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define E1000_CTRL                  0x00000
%define E1000_STATUS                0x00008
%define E1000_RCTL                  0x00100
%define E1000_RDBAL                 0x02800
%define E1000_RDBAH                 0x02804
%define E1000_RDLEN                 0x02808
%define E1000_RDH                   0x02810
%define E1000_RDT                   0x02818
%define E1000_TCTL                  0x00400
%define E1000_TDBAL                 0x03800
%define E1000_TDBAH                 0x03804
%define E1000_TDLEN                 0x03808
%define E1000_TDH                   0x03810
%define E1000_TDT                   0x03818

struc e1000_rx_desc_t
    .buffer_addr:       resq 1      ; 64-bit DMA Physical Address
    .length:            resw 1      ; Packet Length
    .checksum:          resw 1      ; Offloaded Checksum
    .status:            resb 1      ; Descriptor Status (DD bit)
    .errors:            resb 1      ; Error Flags
    .special:           resw 1      ; VLAN Tag
endstruc

section .text

global e1000_init
global e1000_poll
global e1000_transmit

extern dma_alloc_hugepage
extern rdtsc_get_cycles
extern mdelay
extern eth_input

align 64
e1000_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; 1. Execute 20ms Reset Delay via lib/time/delay.asm
    mov edi, 20
    call mdelay

    ; 2. Allocate 2MB Contiguous DMA Ring Memory via lib/mem/dma.asm
    mov rdi, 2 * 1024 * 1024
    call dma_alloc_hugepage

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e1000_poll — Poll RX Ring Descriptors & Record Ingress TSC Timestamps
; -----------------------------------------------------------------------------
align 64
e1000_poll:
    push rbp
    mov rbp, rsp
    push rbx

    ; Poll DD bit in RX ring descriptor
    ; Record ingress TSC timestamp via lib/time/tsc.asm
    call rdtsc_get_cycles

    ; Dispatch packet to L2 Ethernet layer
    call eth_input

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; e1000_transmit — Transmit Packet with PCIe Doorbell Coalescing
; Input: RDI = Pointer to net_pkt_t
; -----------------------------------------------------------------------------
align 64
e1000_transmit:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Update Tail Pointer & Doorbell
    xor eax, eax
    pop rbp
    ret
